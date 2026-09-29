require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "manifest responds successfully for html accept headers" do
    get "/manifest", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    assert_includes response.body, '"start_url": "/"'
  end

  test "manifest uses the Savo Ledger icon" do
    get "/manifest"

    manifest = JSON.parse(response.body)
    icon = manifest.fetch("icons").sole

    assert_includes icon.fetch("src"), "savo-ledger-logo"
    assert_equal "any", icon.fetch("purpose")
  end

  test "service worker responds successfully without origin or referer headers" do
    get "/service-worker", headers: {
      "Accept" => "*/*",
      "DNT" => "1",
      "Sec-GPC" => "1"
    }

    assert_response :success
    assert_equal "application/javascript", response.media_type
  end
end
