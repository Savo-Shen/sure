require "test_helper"

class UserMembershipTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @other_family = families(:empty)
    @admin = users(:family_admin)
    @member = users(:family_member)
  end

  test "membership_for returns the membership for a family the user belongs to" do
    membership = @admin.membership_for(@family)

    assert_equal @family, membership.family
    assert_equal "owner", membership.role
  end

  test "membership_for returns nil for a family the user does not belong to" do
    assert_nil @admin.membership_for(@other_family)
    assert_nil @admin.membership_for(nil)
  end

  test "role_in returns the membership role" do
    assert_equal "owner", @admin.role_in(@family)
    assert_equal "editor", @member.role_in(@family)
    assert_nil @admin.role_in(@other_family)
  end

  test "member_of? reflects membership" do
    assert @admin.member_of?(@family)
    assert_not @admin.member_of?(@other_family)
  end

  test "families returns every family the user has a membership in" do
    assert_includes @admin.families, @family
    assert_not_includes @admin.families, @other_family
  end

  test "changing family_id creates a membership with the mapped legacy role" do
    # Registration / invitation-accept / SSO JIT all assign family_id; the sync
    # hook must guarantee a membership row exists afterwards.
    user = User.new(
      email: "newcomer@example.com",
      password: "password123!",
      first_name: "New",
      last_name: "Joiner",
      role: "member"
    )

    user.update!(family: @other_family)

    membership = user.membership_for(@other_family)
    assert_not_nil membership
    assert_equal "editor", membership.role
  end

  test "changing family_id does not overwrite an existing membership role" do
    # Invitation accept creates the membership with the invited role before the
    # user's family_id moves; the sync hook must treat that row as canonical.
    invite_role_membership = FamilyMembership.create!(user: @member, family: @other_family, role: "admin")

    @member.update!(family: @other_family)

    assert_equal "admin", invite_role_membership.reload.role
    assert_equal 1, @member.family_memberships.where(family: @other_family).count
  end

  test "destroying a user destroys their memberships" do
    assert_difference "FamilyMembership.count", -1 do
      @member.destroy
    end
  end
end
