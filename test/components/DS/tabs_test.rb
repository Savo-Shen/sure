require "test_helper"

class DS::TabsTest < ViewComponent::TestCase
  test "can navigate to the selected tab for server-backed content" do
    render_inline(DS::Tabs.new(
      active_tab: "background_jobs",
      url_param_key: "tab",
      navigate_on_change: true
    )) do |tabs|
      tabs.with_nav do |nav|
        nav.with_btn(id: "background_jobs", label: "Background jobs")
        nav.with_btn(id: "ai", label: "AI status")
      end
      tabs.with_panel(tab_id: "background_jobs") { "Jobs" }
      tabs.with_panel(tab_id: "ai") { "AI" }
    end

    assert_selector "[data-ds--tabs-url-param-key-value='tab']"
    assert_selector "[data-ds--tabs-navigate-on-change-value='true']"
  end

  test "tab buttons never wrap their labels" do
    render_inline(DS::Tabs.new(active_tab: "one")) do |tabs|
      tabs.with_nav do |nav|
        nav.with_btn(id: "one", label: "One")
        nav.with_btn(id: "two", label: "Two")
      end
      tabs.with_panel(tab_id: "one") { "One" }
      tabs.with_panel(tab_id: "two") { "Two" }
    end

    assert_selector "button[role='tab'].whitespace-nowrap", count: 2
  end
end
