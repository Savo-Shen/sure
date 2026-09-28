class BudgetShare < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :viewer, class_name: "User"

  PERMISSIONS = %w[read_write read_only].freeze

  validates :permission, inclusion: { in: PERMISSIONS }
  validates :viewer_id, uniqueness: { scope: :owner_id }
  validate :cannot_share_with_self
  validate :owner_and_viewer_in_same_family

  def read_write?
    permission == "read_write"
  end

  def read_only?
    permission == "read_only"
  end

  private
    def cannot_share_with_self
      errors.add(:viewer, "can't be the owner") if owner_id.present? && owner_id == viewer_id
    end

    def owner_and_viewer_in_same_family
      return unless owner && viewer

      shared_ledger = FamilyMembership.where(user_id: owner.id)
        .where(family_id: FamilyMembership.where(user_id: viewer.id).select(:family_id))
        .exists?
      errors.add(:viewer, "must be in the same family") unless shared_ledger
    end
end
