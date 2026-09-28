require "test_helper"

class FamilyMembershipTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @admin = users(:family_admin)
    @member = users(:family_member)
  end

  test "valid with a permitted role" do
    membership = FamilyMembership.new(user: users(:empty), family: @family, role: "admin")

    assert membership.valid?
  end

  test "invalid with a role outside ROLES" do
    membership = FamilyMembership.new(user: @admin, family: @family, role: "superuser")

    assert_not membership.valid?
  end

  test "invalid with a duplicate user/family pair" do
    duplicate = FamilyMembership.new(user: @member, family: @family, role: "viewer")

    assert_not duplicate.valid?
  end

  test "role_for_legacy_role maps the old single role vocabulary" do
    assert_equal "viewer", FamilyMembership.role_for_legacy_role("guest")
    assert_equal "editor", FamilyMembership.role_for_legacy_role("member")
    assert_equal "owner", FamilyMembership.role_for_legacy_role("admin")
    assert_equal "owner", FamilyMembership.role_for_legacy_role("super_admin")
    assert_equal "editor", FamilyMembership.role_for_legacy_role("unknown")
  end

  test "role_at_least? orders owner > admin > editor > viewer" do
    assert FamilyMembership.role_at_least?("owner", "owner")
    assert FamilyMembership.role_at_least?("owner", "viewer")
    assert FamilyMembership.role_at_least?("admin", "editor")
    assert_not FamilyMembership.role_at_least?("editor", "admin")
    assert_not FamilyMembership.role_at_least?("viewer", "editor")
    assert_not FamilyMembership.role_at_least?("nonsense", "viewer")
  end

  test "role predicate helpers use at-least semantics" do
    admin_membership = FamilyMembership.new(user: @admin, family: @family, role: "admin")

    assert admin_membership.admin?
    assert admin_membership.editor?
    assert_not admin_membership.owner?
  end
end
