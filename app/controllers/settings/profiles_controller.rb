class Settings::ProfilesController < ApplicationController
  layout :layout_for_settings_profile

  def show
    @user = Current.user
    @memberships = Current.family.family_memberships.joins(:user).includes(:user).order("users.created_at", "users.id")
    @pending_invitations = Current.family.invitations.pending
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.profile"), nil ]
    ]
  end

  def destroy
    unless Current.user.admin?
      flash[:alert] = t("settings.profiles.destroy.not_authorized")
      redirect_to settings_profile_path
      return
    end

    # Primary-ledger users only: destroying the user record would also erase
    # the ledgers they joined elsewhere. Revoking a joined member's access is
    # a membership operation, not a user deletion.
    @user = Current.family.users.find(params[:user_id])

    if @user == Current.user
      flash[:alert] = t("settings.profiles.destroy.cannot_remove_self")
      redirect_to settings_profile_path
      return
    end

    if @user.owned_accounts.where.not(family_id: Current.family.id).exists?
      flash[:alert] = t(".member_owns_other_family_data")
      redirect_to settings_profile_path
      return
    end

    # purge, not destroy: it also cleans up ledgers only this user belonged to
    # and hands their accounts to the next most privileged member.
    if @user.purge
      # Also destroy the invitation associated with this user for this family
      Current.family.invitations.find_by(email: @user.email)&.destroy
      flash[:notice] = t(".member_removed")
    else
      flash[:alert] = t(".member_removal_failed")
    end

    redirect_to settings_profile_path
  end

  private

    def layout_for_settings_profile
      Current.user&.ui_layout_intro? ? "application" : "settings"
    end
end
