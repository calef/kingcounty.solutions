# frozen_string_literal: true

require 'logger'
require_relative '../../test_helper'
require 'mayhem/events/stale_event_cleaner'
require 'mayhem/models/event'
require 'mayhem/models/news'

class StaleEventCleanerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    clock_time = Time.utc(2025, 12, 5, 19, 0, 0)
    @cleaner = Mayhem::Events::StaleEventCleaner.new(
      clock: -> { clock_time }
    )
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
  end

  def test_removes_events_older_than_yesterday
    old_event = write_event('old-event', '2025-12-03T10:00:00Z')
    early_today = write_event('early-today', '2025-12-05T10:30:00Z')
    in_progress = write_event('in-progress', '2025-12-05T10:00:00Z', '2025-12-05T20:00:00Z')
    ended_yesterday = write_event('ended-yesterday', '2025-12-04T10:00:00Z', '2025-12-04T18:00:00Z')
    ends_today = write_event('ends-today', '2025-12-05T08:00:00Z', '2025-12-05T18:00:00Z')
    future_event = write_event('future-event', '2025-12-06T10:00:00Z')
    spanning_event = write_event('spanning-event', '2025-12-03T10:00:00Z', '2025-12-06T18:00:00Z')

    @cleaner.run

    refute_event_exists old_event
    assert_event_exists ended_yesterday
    assert_event_exists early_today
    assert_event_exists in_progress
    assert_event_exists ends_today
    assert_event_exists future_event
    assert_event_exists spanning_event
  end

  def test_skips_events_with_missing_start_date
    event = Mayhem::Models::Event.create!({ 'title' => 'missing-date' }, body: '')

    @cleaner.run

    assert_event_exists event.id
  end

  def test_removes_event_links_from_posts
    old_source = 'https://example.com/old'
    future_source = 'https://example.com/future'
    old_event_id = write_event('old-event', '2025-12-03T10:00:00-08:00', source_url: old_source)
    future_event_id = write_event('future-event', '2025-12-06T10:00:00-08:00', source_url: future_source)

    # Create posts that link to events - use actual event IDs
    post1 = write_post('post1', [old_event_id, future_event_id], source_url: old_source)
    post2 = write_post('post2', [future_event_id], source_url: future_source)

    @cleaner.run

    # Verify old event removed
    refute_event_exists old_event_id
    assert_event_exists future_event_id

    # Verify post1 only has future event link
    post1_doc = Mayhem::Models::News.find(post1.id)
    assert_equal [future_event_id], post1_doc.event_ids

    # Verify post2 still has its event link
    post2_doc = Mayhem::Models::News.find(post2.id)
    assert_equal [future_event_id], post2_doc.event_ids
  end

  private

  def assert_event_exists(event_id)
    event = Mayhem::Models::Event.find(event_id)
    assert event, "Expected event '#{event_id}' to exist"
  rescue FMRepo::NotFound
    flunk "Expected event '#{event_id}' to exist"
  end

  def refute_event_exists(event_id)
    Mayhem::Models::Event.find(event_id)
    flunk "Expected event '#{event_id}' to not exist"
  rescue FMRepo::NotFound
    pass
  end

  def write_event(name, start_date, end_date = nil, source_url: nil)
    front_matter = { 'title' => name, 'start_date' => start_date }
    front_matter['end_date'] = end_date if end_date
    front_matter['source_url'] = source_url if source_url
    event = Mayhem::Models::Event.create!(front_matter, body: '')
    event.id
  end

  def write_post(name, event_ids, source_url: nil)
    front_matter = {
      'title' => name,
      'date' => '2025-12-01T12:00:00-08:00',
      'event_ids' => event_ids,
      'source_url' => source_url
    }
    Mayhem::Models::News.create!(front_matter, body: '')
  end
end
