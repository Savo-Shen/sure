require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @session = @user.sessions.create!
    @other_family = families(:empty)
  end

  test "active_family_id is nil for a fresh session" do
    assert_nil @session.active_family_id
  end

  test "switch_active_family! stores the family id in session data" do
    @session.switch_active_family!(@other_family)

    assert_equal @other_family.id, @session.reload.active_family_id
    # Tab preferences share the same jsonb bag and must survive a switch.
    @session.set_preferred_tab("account_sidebar_tab", "asset")
    @session.switch_active_family!(@other_family)
    assert_equal "asset", @session.reload.get_preferred_tab("account_sidebar_tab")
  end

  test "clear_active_family! removes the stored id" do
    @session.switch_active_family!(@other_family)
    @session.clear_active_family!

    assert_nil @session.reload.active_family_id
  end

  test "clear_active_family! is a no-op when nothing is stored" do
    assert_no_changes -> { @session.reload.updated_at } do
      @session.clear_active_family!
    end
  end
end
