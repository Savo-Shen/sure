class ReleaseHighlightsPrefetchJob < ApplicationJob
  # A release note is useful, but it must not compete with account syncs.
  queue_as :low_priority

  def perform(tag)
    Provider::Registry.get_provider(:github)&.fetch_release_notes(tag)
  end
end
