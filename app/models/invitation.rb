class Invitation < ApplicationRecord
  include Encryptable

  belongs_to :family
  belongs_to :inviter, class_name: "User"

  # Encrypt sensitive fields if ActiveRecord encryption is configured
  if encryption_ready?
    encrypts :token, deterministic: true
    encrypts :email, deterministic: true, downcase: true
  end

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true, inclusion: { in: %w[admin member guest] }
  validates :token, presence: true, uniqueness: true
  validate :no_duplicate_pending_invitation_in_family
  validate :inviter_is_admin

  before_validation :normalize_email
  before_validation :generate_token, on: :create
  before_create :remove_expired_duplicates_in_family
  before_create :set_expiration

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  def pending?
    accepted_at.nil? && expires_at > Time.current
  end

  # Accepting joins the invited ledger; it never moves the invitee out of a
  # ledger they already have. The invitee keeps their primary ledger, accounts
  # and provider items, and gains a membership here. (Users without a ledger
  # never reach this method: signup and SSO onboarding assign the invited
  # ledger before the user is persisted, and users.family_id is NOT NULL.)
  def accept_for(user)
    return false if user.blank?
    return false unless pending?
    return false unless emails_match?(user)

    transaction do
      membership = user.family_memberships.find_or_initialize_by(family_id: family_id)
      membership.update!(role: membership_role) if membership.new_record? || membership.role != membership_role

      update!(accepted_at: Time.current)
      family.auto_share_existing_accounts_with(user)
    end
    true
  end

  private

    def emails_match?(user)
      inv_email = email.to_s.strip.downcase
      usr_email = user.email.to_s.strip.downcase
      inv_email.present? && usr_email.present? && inv_email == usr_email
    end

    # Invitation roles speak the legacy vocabulary. Unlike
    # FamilyMembership.role_for_legacy_role (which maps a PRIMARY ledger's
    # admin to owner), an invitee joins as admin, not owner: ownership stays
    # with the ledger's creator.
    def membership_role
      case role.to_s
      when "admin" then "admin"
      when "guest" then "viewer"
      else "editor"
      end
    end

    def generate_token
      loop do
        self.token = SecureRandom.hex(32)
        break unless self.class.exists?(token: token)
      end
    end

    def set_expiration
      self.expires_at = 3.days.from_now
    end

    # An expired, never-accepted invitation still occupies the partial unique
    # index `index_invitations_on_email_and_family_id_pending` (predicate
    # `accepted_at IS NULL`), but the `pending` scope treats it as gone because
    # of the `expires_at > now` clause. The duplicate-guard validation therefore
    # passes, and the INSERT collides with the index, raising RecordNotUnique.
    # Removing the stale row inside the create transaction frees the slot so the
    # re-invite can proceed. It runs only after validations pass, so a still
    # pending (non-expired) invitation can never be removed here.
    def remove_expired_duplicates_in_family
      return if email.blank?

      scope = self.class.where(family_id: family_id, accepted_at: nil)
                        .where("expires_at <= ?", Time.current)

      scope = if self.class.encryption_ready?
        scope.where(email: email)
      else
        scope.where("LOWER(email) = ?", email.to_s.strip.downcase)
      end

      scope.delete_all
    end

    def normalize_email
      self.email = email.to_s.strip.downcase if email.present?
    end

    def no_duplicate_pending_invitation_in_family
      return if email.blank?

      scope = self.class.pending.where(family_id: family_id)
      scope = scope.where.not(id: id) if persisted?

      exists = if self.class.encryption_ready?
        scope.where(email: email).exists?
      else
        scope.where("LOWER(email) = ?", email.to_s.strip.downcase).exists?
      end

      errors.add(:email, "has already been invited to this family") if exists
    end

    def inviter_is_admin
      inviter.admin?
    end
end
