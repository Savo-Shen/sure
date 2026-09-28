class FamilyMembership < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  belongs_to :user
  belongs_to :family

  # Stored in ascending privilege order: owner(0) > admin(1) > editor(2) > viewer(3).
  enum :role, ROLES.index_with(&:itself), validate: true

  validates :user_id, uniqueness: { scope: :family_id }

  # The membership is the source of truth for roles; users.role mirrors the
  # primary ledger's membership in the legacy vocabulary.
  after_save :project_role_onto_user, if: -> { saved_change_to_role? && primary? }

  # role is a string column, so SQL ordering on it is alphabetical rather than
  # privilege order. This CASE restores owner > admin > editor > viewer for the
  # few places that must pick "the most privileged member" in the query layer.
  # Ties break on the USER's created_at/id (not the membership's), matching how
  # account age used to decide fallbacks before memberships existed.
  PRIVILEGE_ORDER_SQL = "CASE family_memberships.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 WHEN 'editor' THEN 2 ELSE 3 END".freeze
  scope :by_privilege, -> { joins(:user).order(Arel.sql(PRIVILEGE_ORDER_SQL), "users.created_at", "users.id") }

  # Maps a legacy users.role value onto the membership role set. Kept next to
  # the role list so the backfill migration and the runtime sync hook can never
  # disagree about the mapping.
  def self.role_for_legacy_role(legacy_role)
    case legacy_role.to_s
    when "guest" then "viewer"
    when "member" then "editor"
    when "admin", "super_admin" then "owner"
    else "editor"
    end
  end

  # Inverse of role_for_legacy_role, for when a membership becomes a user's
  # primary family and users.role has to describe it again.
  def self.legacy_role_for(membership_role)
    case membership_role.to_s
    when "owner", "admin" then "admin"
    when "viewer" then "guest"
    else "member"
    end
  end

  def self.same_legacy_level?(role_a, role_b)
    legacy_role_for(role_a) == legacy_role_for(role_b)
  end

  # True when +actual+ is at least as privileged as +minimum+, e.g.
  # role_at_least?("admin", "editor") == true. Works on strings so it can
  # answer for a role the record doesn't currently hold.
  def self.role_at_least?(actual, minimum)
    actual_index = ROLES.index(actual.to_s)
    minimum_index = ROLES.index(minimum.to_s)

    actual_index.present? && minimum_index.present? && actual_index <= minimum_index
  end

  def role_at_least?(minimum)
    self.class.role_at_least?(role, minimum)
  end

  # Role label in the legacy vocabulary the UI still speaks. The primary
  # ledger keeps users.role so super_admin stays distinguishable.
  def legacy_role
    primary? ? user.role : self.class.legacy_role_for(role)
  end

  def primary?
    user.family_id == family_id
  end

  # super_admin holds every role in every ledger, so never gets a read-only share.
  def default_share_permission
    viewer? && !user.super_admin? ? "read_only" : "read_write"
  end

  private

    def project_role_onto_user
      return if user.super_admin?

      legacy = self.class.legacy_role_for(role)
      user.update!(role: legacy) unless user.role == legacy
    end
end
