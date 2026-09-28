class UsersController < ApplicationController
  before_action :set_user
  before_action :ensure_admin, only: %i[reset reset_with_sample_data]

  def resend_confirmation_email
    if @user.resend_confirmation_email
      redirect_to settings_profile_path, notice: t(".success")
    else
      redirect_to settings_profile_path, alert: t(".no_pending_change")
    end
  end

  def update
    @user = Current.user
    return redirect_back_or_to(settings_preferences_path, alert: t("shared.ledger_switched")) if stale_ledger_form?
    return if admin_family_change_requested? && !ensure_admin

    if email_changed?
      if @user.initiate_email_change(user_params[:email])
        if Rails.application.config.app_mode.self_hosted? && !Setting.require_email_confirmation
          handle_redirect(t(".success"))
        else
          redirect_to settings_profile_path, notice: t(".email_change_initiated")
        end
      else
        error_message = @user.errors.any? ? @user.errors.full_messages.to_sentence : t(".email_change_failed")
        redirect_to settings_profile_path, alert: error_message
      end
    else
      was_ai_enabled = @user.ai_enabled
      user_attrs = user_params.except(:redirect_to, :delete_profile_image, :family_attributes)
      if update_user_and_ledger(user_attrs, user_params[:family_attributes])
        @user.profile_image.purge if should_purge_profile_image?

        # Add a special notice if AI was just enabled or disabled
        notice = if !was_ai_enabled && @user.ai_enabled
          "AI Assistant has been enabled successfully."
        elsif was_ai_enabled && !@user.ai_enabled
          "AI Assistant has been disabled."
        else
          t(".success")
        end

        respond_to do |format|
          format.html { handle_redirect(notice) }
          format.json { head :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to settings_profile_path, alert: @user.errors.full_messages.to_sentence }
          format.json { render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end
  end

  def reset
    FamilyResetJob.perform_later(Current.family)
    redirect_to settings_profile_path, notice: t(".success")
  end

  def reset_with_sample_data
    FamilyResetJob.perform_later(Current.family, load_sample_data_for_email: @user.email)
    redirect_to settings_profile_path, notice: t(".success")
  end

  def destroy
    if @user.deactivate
      Current.session.destroy
      redirect_to root_path, notice: t(".success")
    else
      redirect_to settings_profile_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def rule_prompt_settings
    @user.update!(rule_prompt_settings_params)
    redirect_back_or_to settings_profile_path
  end

  private
    # Ledger settings belong to the active ledger, which is not necessarily the
    # user's primary family, so they bypass the user's nested family attributes.
    def update_user_and_ledger(user_attrs, ledger_attrs)
      return @user.update(user_attrs) if ledger_attrs.blank?

      ledger = Current.family
      User.transaction do
        unless ledger.update(ledger_attrs.except(:id)) && @user.update(user_attrs)
          ledger.errors.each { |error| @user.errors.import(error, attribute: :"family.#{error.attribute}") }
          raise ActiveRecord::Rollback
        end
      end
      @user.errors.empty?
    end

    def handle_redirect(notice)
      case user_params[:redirect_to]
      when "onboarding_preferences"
        redirect_to preferences_onboarding_path
      when "home"
        redirect_to root_path
      when "preferences"
        redirect_to settings_preferences_path, notice: notice
      when "goals"
        redirect_to goals_onboarding_path
      when "trial"
        redirect_to trial_onboarding_path
      when "appearance"
        redirect_to settings_appearance_path, notice: notice
      when "ai_prompts"
        redirect_to settings_ai_prompts_path, notice: notice
      else
        redirect_to settings_profile_path, notice: notice
      end
    end

    def should_purge_profile_image?
      user_params[:delete_profile_image] == "1" &&
        user_params[:profile_image].blank?
    end

    def email_changed?
      user_params[:email].present? && user_params[:email] != @user.email
    end

    def rule_prompt_settings_params
      params.require(:user).permit(:rule_prompt_dismissed_at, :rule_prompts_disabled)
    end

    def user_params
      # Viewers are read-only in the ledger; renaming it or changing its
      # currency affects everyone, so those need admin.
      family_attrs = [ :id ]
      family_attrs.push(:country, :date_format, :timezone, :locale, :month_start_day) if Current.user.member?
      if Current.user.admin?
        family_attrs.push(:name, :currency)
        family_attrs.push(:personal_budgets, :household_budget_enabled) # Needed for updating existing family
        family_attrs.push(:moniker, :default_account_sharing)
        family_attrs << { enabled_currencies: [] }
      end

      params.require(:user).permit(
        :first_name, :last_name, :email, :profile_image, :redirect_to, :delete_profile_image, :onboarded_at,
        :show_sidebar, :default_period, :default_account_order, :show_ai_sidebar, :ai_enabled, :theme, :set_onboarding_preferences_at, :set_onboarding_goals_at, :locale,
        family_attributes: family_attrs,
        goals: []
      )
    end

    def set_user
      @user = Current.user
    end

    # Ledger forms carry the id of the ledger they were rendered for; after a
    # switch in another tab that is no longer Current.family.
    def stale_ledger_form?
      form_family_id = params.dig(:user, :family_attributes, :id).presence
      form_family_id.present? && form_family_id != Current.family.id
    end

    def admin_family_change_requested?
      family_attrs = params.dig(:user, :family_attributes)
      return false if family_attrs.blank?

      moniker_changed = family_attrs[:moniker].present? && family_attrs[:moniker] != Current.family.moniker
      sharing_changed = family_attrs[:default_account_sharing].present? && family_attrs[:default_account_sharing] != Current.family.default_account_sharing
      enabled_currencies_changed = family_attrs.key?(:enabled_currencies)
      personal_budgets_changed = family_attrs.key?(:personal_budgets)
      household_budget_enabled_changed = family_attrs.key?(:household_budget_enabled)

      moniker_changed || sharing_changed || enabled_currencies_changed || personal_budgets_changed || household_budget_enabled_changed
    end

    def ensure_admin
      return true if Current.user.admin?

      redirect_to settings_profile_path, alert: I18n.t("users.reset.unauthorized")
      false
    end
end
