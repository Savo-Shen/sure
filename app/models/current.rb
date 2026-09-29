class Current < ActiveSupport::CurrentAttributes
  attribute :user_agent, :ip_address

  attribute :session
  attribute :latest_sync_by_syncable, :latest_completed_sync_by_syncable, :syncing_by_syncable
  attribute :resolved_user, :resolved_family, :user_context_loaded, :family_context_loaded

  # The family (ledger) all scoped queries run against. Resolves to the
  # session's active family when the user has switched ledgers and still holds
  # a membership there; otherwise falls back to the user's primary family
  # (users.family_id). Membership is re-validated on every read so a revoked
  # membership can never leak another ledger's data through a stale session
  # value — the fallback just brings the user back to their primary family.
  #
  # The resolved context is stored in declared CurrentAttributes so reset
  # clears it between requests. This avoids repeatedly walking memberships
  # from the application layout and its helpers while remaining safe when a
  # thread is reused for another request.
  def family
    return resolved_family if family_context_loaded

    self.resolved_family = active_family_from_session || user&.family
    self.family_context_loaded = true
    resolved_family
  end

  def user
    return resolved_user if user_context_loaded

    self.resolved_user = impersonated_user || session&.user
    self.user_context_loaded = true
    resolved_user
  end

  def impersonated_user
    session&.active_impersonator_session&.impersonated
  end

  def true_user
    session&.user
  end

  def accessible_accounts
    return family&.accounts unless user
    family.accounts.accessible_by(user)
  end

  def finance_accounts
    return family&.accounts unless user
    family.accounts.included_in_finances_for(user)
  end

  def accessible_entries
    return family&.entries unless user
    family.entries.joins(:account).merge(Account.accessible_by(user))
  end

  # Used for invalidating caches whose results depend on the current user's
  # account-share access (e.g. the transactions index's uncategorized count
  # and projected recurring list, which are scoped to accessible accounts).
  # Changes whenever an AccountShare granting/revoking the user's access is
  # created, updated, or destroyed.
  def account_share_version
    return "0-" unless user
    shares = AccountShare.where(user: user)
    "#{shares.count}-#{shares.maximum(:updated_at)&.to_f}"
  end

  private

    def active_family_from_session
      active_id = session&.active_family_id
      return if active_id.blank? || user.blank?

      user.family_memberships.detect { |membership| membership.family_id == active_id }&.family
    end
end
