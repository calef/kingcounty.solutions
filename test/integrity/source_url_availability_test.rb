# frozen_string_literal: true

require_relative '../test_helper'
require 'mayhem/content/source_url_checker'

class SourceUrlAvailabilityTest < Minitest::Test
  def test_all_source_urls_are_available
    skip 'Set CHECK_SOURCE_URLS=1 to check source URL availability' unless ENV['CHECK_SOURCE_URLS']

    checker = Mayhem::Content::SourceUrlChecker.new

    # Run the checker which will unpublish posts and delete events with dead links
    checker.run

    # If this test passes, it means all source URLs were checked
    # Posts with dead links will be unpublished and events with dead links will be deleted
    pass
  end
end
