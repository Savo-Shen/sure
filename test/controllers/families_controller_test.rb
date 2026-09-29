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

  test "new renders the create ledger form" do
    get new_family_path

    assert_response :success
    assert_select "form[action=?]", families_path
  end

  test "create makes the creator the owner of the new ledger and switches to it" do
    assert_difference [ "Family.count", "FamilyMembership.count" ], 1 do
      post families_path, params: { family: { name: "Side Business", currency: "EUR" } }
    end

    family = Family.find_by!(name: "Side Business")

    assert_equal "EUR", family.currency
    assert_equal "owner", @user.family_memberships.find_by!(family: family).role
    assert_redirected_to root_path
    assert_equal I18n.t("families.create.created", family: "Side Business"), flash[:notice]
    assert_equal family.id, Current.session.reload.active_family_id
  end

  test "create does not change the user's role in the ledger they came from" do
    post families_path, params: { family: { name: "Side Business", currency: "USD" } }

    assert_equal "owner", @user.family_memberships.find_by!(family: @user.family).role
    assert_equal "admin", @user.reload.role
  end

  test "create inherits the current ledger's regional settings" do
    @user.family.update!(
      currency: "EUR",
      country: "DE",
      locale: "de",
      date_format: "%d.%m.%Y",
      timezone: "Europe/Berlin",
      month_start_day: 15
    )

    post families_path, params: { family: { name: "Zweites Buch" } }

    family = Family.find_by!(name: "Zweites Buch")
    assert_equal [ "EUR", "DE", "de", "%d.%m.%Y", "Europe/Berlin", 15 ],
                 [ family.currency, family.country, family.locale, family.date_format, family.timezone, family.month_start_day ]
  end

  test "create rejects a currency outside the ledger's enabled ones" do
    @user.family.update!(currency: "USD", enabled_currencies: %w[USD EUR])

    post families_path, params: { family: { name: "Yen ledger", currency: "JPY" } }

    assert_equal "USD", Family.find_by!(name: "Yen ledger").currency
  end

  test "create accepts a currency from the ledger's enabled ones" do
    @user.family.update!(currency: "USD", enabled_currencies: %w[USD EUR])

    post families_path, params: { family: { name: "Euro ledger", currency: "EUR" } }

    assert_equal "EUR", Family.find_by!(name: "Euro ledger").currency
  end
end
