class FamilyMembership < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  belongs_to :user
  belongs_to :family

  # Stored in ascending privilege order: owner(0) > admin(1) > editor(2) > viewer(3).
  enum :role, ROLES.index_with(&:itself), validate: true

  validates :user_id, uniqueness: { scope: :family_id }

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

  def owner?
    role_at_least?("owner")
  end

  def admin?
    role_at_least?("admin")
  end

  def editor?
    role_at_least?("editor")
  end
end
