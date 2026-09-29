require "test_helper"

class ReleaseHighlightsPrefetchJobTest < ActiveJob::TestCase
  test "fetches release notes through the configured GitHub provider" do
    provider = mock
    provider.expects(:fetch_release_notes).with("v1.2.3")
    Provider::Registry.expects(:get_provider).with(:github).returns(provider)

    ReleaseHighlightsPrefetchJob.perform_now("v1.2.3")
  end

  test "does nothing when GitHub is unavailable" do
    Provider::Registry.expects(:get_provider).with(:github).returns(nil)

    ReleaseHighlightsPrefetchJob.perform_now("v1.2.3")
  end
end
