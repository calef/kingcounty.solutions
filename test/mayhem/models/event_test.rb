# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/event'

class EventModelTest < Minitest::Test
  def test_creates_and_reads_events
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      record = Mayhem::Models::Event.create!(
        {
          'title' => 'Community Meeting',
          'start_date' => '2025-12-20T09:00:00-08:00',
          'end_date' => '2025-12-20T10:30:00-08:00',
          'location' => 'Community Center',
          'organization_title' => 'Test Organization',
          'source_url' => 'https://example.com/event'
        },
        body: 'A test community event.'
      )

      assert_equal '_events/community-meeting.md', record.id
      assert_equal 'Community Meeting', record.title
      assert_equal '2025-12-20T09:00:00-08:00', record.start_date
      assert_equal '2025-12-20T10:30:00-08:00', record.end_date
      assert_equal 'Community Center', record.location
      assert_equal 'Test Organization', record.organization_title
      assert_equal 'https://example.com/event', record.source_url
      assert_equal 'A test community event.', record.body.strip

      loaded = Mayhem::Models::Event.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Community Meeting', loaded.title
    end
  end
end
