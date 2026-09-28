class Session < ApplicationRecord
  include Encryptable

  # Encrypt user_agent if ActiveRecord encryption is configured
  if encryption_ready?
    encrypts :user_agent
  end

  belongs_to :user, counter_cache: :sessions_count
  belongs_to :active_impersonator_session,
    -> { where(status: :in_progress) },
    class_name: "ImpersonationSession",
    optional: true

  before_create :capture_session_info

  after_create :update_user_last_login

  def prev_transaction_page_params
    super || {}
  end

  # The family this session last switched to via the ledger switcher, or nil
  # when the user has never switched (or the value was cleared). Stored in the
  # session's jsonb `data` alongside tab preferences; validity against the
  # user's memberships is enforced by Current when resolving the family.
  def active_family_id
    data["active_family_id"]
  end

  def switch_active_family!(family)
    data["active_family_id"] = family.id
    save!
  end

  def clear_active_family!
    return if active_family_id.blank?

    data.delete("active_family_id")
    save!
  end

  def get_preferred_tab(tab_key)
    data.dig("tab_preferences", tab_key)
  end

  def set_preferred_tab(tab_key, tab_value)
    data["tab_preferences"] ||= {}
    data["tab_preferences"][tab_key] = tab_value
    save!
  end

  private

    def capture_session_info
      self.user_agent = Current.user_agent
      raw_ip = Current.ip_address
      self.ip_address = raw_ip
      self.ip_address_digest = Digest::SHA256.hexdigest(raw_ip.to_s) if raw_ip.present?
    end

    def update_user_last_login
      user.update_columns(last_login_at: created_at)
    end
end
