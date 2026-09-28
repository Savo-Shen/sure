require "test_helper"

class UserMembershipTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @other_family = families(:empty)
    @admin = users(:family_admin)
    @member = users(:family_member)
  end

  teardown { Current.reset }

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

  test "changing only the legacy role re-syncs the primary membership" do
    @admin.update!(role: "member")
    assert_equal "editor", @admin.role_in(@family)

    @admin.update!(role: "guest")
    assert_equal "viewer", @admin.role_in(@family)
  end

  test "moving primary family revokes the membership in the old ledger" do
    @member.update!(family: @other_family)

    assert_not @member.member_of?(@family)
    assert @member.member_of?(@other_family)
  end

  test "moving keeps memberships in ledgers other than the one left" do
    third = Family.create!(name: "Third ledger", currency: "USD")
    FamilyMembership.create!(user: @member, family: third, role: "viewer")

    @member.update!(family: @other_family)

    assert_equal "viewer", @member.role_in(third)
  end

  test "destroying a family re-homes members who belong to another ledger" do
    doomed = Family.create!(name: "Doomed ledger", currency: "USD")
    multi = doomed.users.create!(email: "multi@example.com", password: user_password_test, role: "member")
    solo = doomed.users.create!(email: "solo@example.com", password: user_password_test, role: "admin")
    FamilyMembership.create!(user: multi, family: @other_family, role: "viewer")

    assert doomed.destroy

    multi.reload
    assert_equal @other_family, multi.family
    assert_equal "guest", multi.role
    assert_equal "viewer", multi.role_in(@other_family)
    assert_nil multi.membership_for(doomed)
    assert_not User.exists?(solo.id), "users with no other ledger are still removed"
  end

  test "purge removes secondary ledgers the user was the only member of" do
    home = Family.create!(name: "Home ledger", currency: "USD")
    shared = Family.create!(name: "Shared ledger", currency: "USD")
    side = Family.create!(name: "Side ledger", currency: "USD")
    user = home.users.create!(email: "purged@example.com", password: user_password_test, role: "admin")
    partner = home.users.create!(email: "partner@example.com", password: user_password_test, role: "member")
    FamilyMembership.create!(user: user, family: shared, role: "owner")
    FamilyMembership.create!(user: partner, family: shared, role: "editor")
    FamilyMembership.create!(user: user, family: side, role: "owner")

    user.purge

    assert_not User.exists?(user.id)
    assert_not Family.exists?(side.id), "a ledger with no other members is removed"
    assert Family.exists?(shared.id), "ledgers with other members survive"
    assert Family.exists?(home.id)
  end

  test "role predicates resolve against the active ledger, not the primary one" do
    FamilyMembership.create!(user: @admin, family: @other_family, role: "viewer")
    session = @admin.sessions.create!
    session.switch_active_family!(@other_family)
    Current.session = session

    assert_not @admin.admin?
    assert_not @admin.member?
    assert @admin.guest?
  end

  test "role predicates follow a switch back to the ledger the user owns" do
    FamilyMembership.create!(user: @admin, family: @other_family, role: "viewer")
    session = @admin.sessions.create!
    session.switch_active_family!(@family)
    Current.session = session

    assert @admin.admin?
    assert @admin.member?
    assert_not @admin.guest?
  end

  test "role predicates honor an editor membership in the active ledger" do
    session = @member.sessions.create!
    session.switch_active_family!(@family)
    Current.session = session

    assert @member.member?
    assert_not @member.admin?
    assert_not @member.guest?
  end

  test "role predicates fall back to the legacy role column without a request context" do
    Current.reset

    assert @admin.admin?
    assert @admin.member?
    assert_not @admin.guest?
    assert @member.member?
    assert_not @member.admin?
  end
end
