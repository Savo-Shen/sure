class ApplicationController < ActionController::Base
  include RestoreLayoutPreferences, Onboardable, Localize, AutoSync, Authentication, Invitable,
          SelfHostable, StoreLocation, Impersonatable, Breadcrumbable,
          FeatureGuardable, Notifiable, SafePagination, AccountAuthorizable,
          PreviewGateable
  include Pundit::Authorization
  include CodespacesForgeryProtection

  include Pagy::Backend

  # Pundit uses current_user by default, but this app uses Current.user
  def pundit_user
    Current.user
  end

  # For ledger-wide resources (categories, tags, rules, budgets...): viewers
  # may browse them but not open write forms or submit writes.
  def self.require_ledger_editor_for_writes(**options)
    before_action :require_ledger_editor!, **options, unless: -> { request.get? && !action_name.in?(%w[new edit]) }
  end

  before_action :detect_os
  before_action :set_default_chat
  before_action :set_active_storage_url_options
  before_action :reject_stale_ledger_write

  helper_method :demo_config, :demo_host_match?, :show_demo_warning?, :current_sidekiq_health

  private
    def accept_pending_invitation_for(user)
      return false if user.blank?

      token = session[:pending_invitation_token]
      return false if token.blank?

      invitation = Invitation.pending.find_by(token: token.to_s)
      return false unless invitation
      return false unless invitation.accept_for(user)

      session.delete(:pending_invitation_token)
      true
    end

    def store_pending_invitation_if_valid
      token = params[:invitation].to_s.presence
      return if token.blank?

      invitation = Invitation.pending.find_by(token: token)
      session[:pending_invitation_token] = token if invitation
    end

    def require_admin!
      return if Current.user&.admin?

      respond_to do |format|
        format.html { redirect_to accounts_path, alert: t("shared.require_admin") }
        format.turbo_stream { head :forbidden }
        format.json { head :forbidden }
        format.any { head :forbidden }
      end
    end

    # Viewers are read-only guests of a ledger.
    def require_ledger_editor!
      return if Current.user&.member?

      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: t("shared.require_ledger_editor") }
        format.turbo_stream { head :forbidden }
        format.json { head :forbidden }
        format.any { head :forbidden }
      end
    end

    # The active ledger lives in the session, which every tab shares. Pages
    # stamp the ledger they were rendered for into X-Active-Family-Id (see
    # application.js); a write from a tab left on another ledger is refused
    # instead of landing in whichever ledger was switched to since.
    def reject_stale_ledger_write
      return if request.get? || request.head?

      stamped_family_id = request.headers["X-Active-Family-Id"].presence
      return if stamped_family_id.nil? || Current.family.nil? || stamped_family_id == Current.family.id

      respond_to do |format|
        format.json { head :conflict }
        format.any { redirect_back_or_to root_path, alert: t("shared.ledger_switched"), status: :see_other }
      end
    end

    def detect_os
      user_agent = request.user_agent
      @os = case user_agent
      when /Windows/i then "windows"
      when /Macintosh/i then "mac"
      when /Linux/i then "linux"
      when /Android/i then "android"
      when /iPhone|iPad/i then "ios"
      else ""
      end
    end

    # By default, we show the user the last chat they interacted with
    def set_default_chat
      @last_viewed_chat = Current.user&.last_viewed_chat
      @last_viewed_chat = nil unless @last_viewed_chat&.family_id == Current.family&.id
      @chat = @last_viewed_chat
    end

    def set_active_storage_url_options
      ActiveStorage::Current.url_options = {
        protocol: request.protocol,
        host: request.host,
        port: request.optional_port
      }
    end

    def demo_config
      Rails.application.config_for(:demo)
    rescue RuntimeError, Errno::ENOENT, Psych::SyntaxError
      nil
    end

    def demo_host_match?(demo = demo_config)
      return false unless demo.is_a?(Hash) && demo["hosts"].present?

      demo["hosts"].include?(request.host)
    end

    def show_demo_warning?
      demo_host_match?
    end

    # Returns the current Sidekiq health snapshot in self-hosted mode and
    # `nil` in managed mode. Memoized per request and additionally cached
    # across requests by `SidekiqHealth.current`, so an authenticated page
    # render adds at most one Redis round-trip per cache window — not three
    # per request. Returns `nil` (not a healthy stand-in) in managed mode
    # so callers must explicitly handle the "check disabled" case; the
    # banner already gates on `Current.user&.super_admin?` and `present?`.
    def current_sidekiq_health
      return @current_sidekiq_health if defined?(@current_sidekiq_health)
      @current_sidekiq_health = Rails.application.config.app_mode.self_hosted? ? SidekiqHealth.current : nil
    end

    def accessible_accounts
      Current.accessible_accounts
    end
    helper_method :accessible_accounts

    def finance_accounts
      Current.finance_accounts
    end
    helper_method :finance_accounts
end
