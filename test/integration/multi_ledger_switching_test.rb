require "test_helper"

class MultiLedgerSwitchingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @primary = @user.family
    @ledger_b = families(:empty)
    FamilyMembership.create!(user: @user, family: @ledger_b, role: "owner")

    @account_b = @ledger_b.accounts.create!(
      name: "Ledger B Checking",
      balance: 500,
      currency: "USD",
      accountable: Depository.new,
      owner: @user
    )
    @account_b.entries.create!(
      name: "Ledger B coffee",
      date: Date.current,
      amount: 5,
      currency: "USD",
      entryable: Transaction.new
    )

    sign_in @user
    post switch_family_path(family_id: @ledger_b.id)
  end

  test "account pages show the switched-to ledger's accounts" do
    get account_path(@account_b)
    assert_response :success

    get accounts_path
    assert_response :success
    assert_includes response.body, "Ledger B Checking"
  end

  test "transactions index lists the switched-to ledger's transactions" do
    get transactions_path
    assert_response :success
    assert_includes response.body, "Ledger B coffee"
  end

  test "primary ledger accounts are not reachable while another ledger is active" do
    get account_path(accounts(:depository))
    assert_response :not_found
  end

  test "reports and cash flow render for the switched-to ledger" do
    get reports_path
    assert_response :success
  end

  test "intro layout users can still reach the ledger switcher" do
    intro_user = users(:intro_user)
    FamilyMembership.create!(user: intro_user, family: @primary, role: "viewer")
    sign_in intro_user

    get chats_path
    assert_response :success
    assert_select "form[action=?]", switch_family_path(family_id: @primary.id)
  end
end
