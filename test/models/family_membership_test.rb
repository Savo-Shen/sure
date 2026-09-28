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

  test "enum predicates are exact; role_at_least? carries the hierarchy" do
    admin_membership = FamilyMembership.new(user: @admin, family: @family, role: "admin")

    assert admin_membership.admin?
    assert_not admin_membership.editor?
    assert_not admin_membership.owner?
    assert admin_membership.role_at_least?("editor")
    assert_not admin_membership.role_at_least?("owner")
  end

  test "legacy_role_for maps membership roles back to the legacy vocabulary" do
    assert_equal "admin", FamilyMembership.legacy_role_for("owner")
    assert_equal "admin", FamilyMembership.legacy_role_for("admin")
    assert_equal "member", FamilyMembership.legacy_role_for("editor")
    assert_equal "guest", FamilyMembership.legacy_role_for("viewer")
  end

  test "by_privilege orders owner, admin, editor, viewer" do
    family = families(:empty)
    roles = family.family_memberships.by_privilege.map(&:role)

    assert_equal roles.sort_by { |role| FamilyMembership::ROLES.index(role) }, roles
  end
end
