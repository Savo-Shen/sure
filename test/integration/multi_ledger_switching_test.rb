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

  test "a write stamped with a ledger other than the active one is refused" do
    assert_no_difference -> { Category.count } do
      post categories_path,
        params: { category: { name: "Stale tab category", color: "#000000" } },
        headers: { "X-Active-Family-Id" => @primary.id }
    end

    assert_response :see_other
    assert_equal I18n.t("shared.ledger_switched"), flash[:alert]
  end

  test "a write stamped with the active ledger goes through" do
    assert_difference -> { @ledger_b.categories.count }, 1 do
      post categories_path,
        params: { category: { name: "Current tab category", color: "#000000" } },
        headers: { "X-Active-Family-Id" => @ledger_b.id }
    end
  end

  test "a stale tab can still switch ledgers" do
    post switch_family_path(family_id: @primary.id), headers: { "X-Active-Family-Id" => @primary.id }
    assert_equal I18n.t("families.switch.switched", family: @primary.name), flash[:notice]
  end

  test "pages stamp the active ledger for later writes" do
    get accounts_path
    assert_select "meta[name=active-family-id][content=?]", @ledger_b.id
  end

  test "a viewer can browse but not change ledger-wide data" do
    viewer = users(:family_member)
    FamilyMembership.create!(user: viewer, family: @ledger_b, role: "viewer")
    sign_in viewer
    post switch_family_path(family_id: @ledger_b.id)
    name_before, currency_before = @ledger_b.name, @ledger_b.currency

    get categories_path
    assert_response :success

    get new_category_path
    assert_redirected_to root_path

    assert_no_difference -> { @ledger_b.categories.count + @ledger_b.tags.count + @ledger_b.accounts.count } do
      post categories_path, params: { category: { name: "Viewer category", color: "#000000" } }
      post tags_path, params: { tag: { name: "Viewer tag", color: "#000000" } }
      post depositories_path, params: { account: { name: "Viewer cash", balance: 1, currency: "USD", accountable_type: "Depository" } }
    end
    assert_equal I18n.t("shared.require_ledger_editor"), flash[:alert]

    patch user_path(viewer), params: {
      user: { redirect_to: "preferences", family_attributes: { id: @ledger_b.id, name: "Viewer rename", currency: "JPY", date_format: "%d.%m.%Y" } }
    }
    @ledger_b.reload
    assert_equal [ name_before, currency_before ], [ @ledger_b.name, @ledger_b.currency ]
    assert_not_equal "%d.%m.%Y", @ledger_b.date_format
  end

  test "an editor can change display settings but not the ledger name or currency" do
    editor = users(:family_member)
    FamilyMembership.create!(user: editor, family: @ledger_b, role: "editor")
    sign_in editor
    post switch_family_path(family_id: @ledger_b.id)
    name_before, currency_before = @ledger_b.name, @ledger_b.currency

    patch user_path(editor), params: {
      user: { redirect_to: "preferences", family_attributes: { id: @ledger_b.id, name: "Editor rename", currency: "JPY", date_format: "%d.%m.%Y" } }
    }

    @ledger_b.reload
    assert_equal [ name_before, currency_before ], [ @ledger_b.name, @ledger_b.currency ]
    assert_equal "%d.%m.%Y", @ledger_b.date_format
  end

  test "intro layout users can still reach the ledger switcher" do
    intro_user = users(:intro_user)
    FamilyMembership.create!(user: intro_user, family: @primary, role: "viewer")
    sign_in intro_user

    get chats_path
    assert_response :success
    assert_select "form[action=?]", switch_family_path(family_id: @primary.id)
    assert_select "a[href=?]", new_family_path
  end

  test "the sidebar switcher offers a new ledger with a single ledger too" do
    get transactions_path
    assert_response :success

    assert_select "a[href=?]", new_family_path
  end
end
