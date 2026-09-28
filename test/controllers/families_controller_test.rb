require "test_helper"

class FamiliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
    @other_family = families(:empty)
  end

  test "switch stores the family id on the session and redirects" do
    FamilyMembership.create!(user: @user, family: @other_family, role: "editor")

    post switch_family_path(family_id: @other_family.id)

    assert_redirected_to root_path
    assert_equal @other_family.id, Current.session.reload.active_family_id
  end

  test "switch makes Current resolve the newly active family" do
    FamilyMembership.create!(user: @user, family: @other_family, role: "editor")

    post switch_family_path(family_id: @other_family.id)

    Current.reset
    Current.session = @user.sessions.order(:created_at).last
    assert_equal @other_family, Current.family
  end

  test "switch rejects a family the user is not a member of" do
    assert_no_changes -> { Current.session.reload.data } do
      post switch_family_path(family_id: @other_family.id)
    end

    assert_redirected_to root_path
    assert_equal I18n.t("families.switch.not_a_member"), flash[:alert]
  end

  test "switch rejects an unknown family id" do
    post switch_family_path(family_id: SecureRandom.uuid)

    assert_redirected_to root_path
    assert_equal I18n.t("families.switch.not_a_member"), flash[:alert]
  end
end
