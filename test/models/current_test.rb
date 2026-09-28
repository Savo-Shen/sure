require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
  end

  test "family returns user family" do
    Current.session = @user.sessions.create!
    assert_equal @user.family, Current.family
  end

  test "family returns nil without a session" do
    assert_nil Current.family
  end

  test "family follows the session's active family when user is a member" do
    other_family = families(:empty)
    FamilyMembership.create!(user: @user, family: other_family, role: "editor")

    session = @user.sessions.create!
    session.switch_active_family!(other_family)
    Current.session = session

    assert_equal other_family, Current.family
  end

  test "family falls back to primary family when session has no active family" do
    session = @user.sessions.create!
    Current.session = session

    assert_equal @user.family, Current.family
  end

  test "family falls back to primary family when active family is not a membership" do
    stranger_family = families(:empty)
    session = @user.sessions.create!
    session.switch_active_family!(stranger_family)
    Current.session = session

    assert_not @user.member_of?(stranger_family)
    assert_equal @user.family, Current.family
  end
end
