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

    refute_path_exists old_event
    assert_path_exists ended_yesterday
    assert_path_exists early_today
    assert_path_exists in_progress
    assert_path_exists ends_today
    assert_path_exists future_event
    assert_path_exists spanning_event
  end

  def test_skips_events_with_missing_start_date
    event = Mayhem::Models::Event.create!({ 'title' => 'missing-date' }, body: '')
    event_path = event.path.to_s

    @cleaner.run

    assert_path_exists event_path
  end

  def test_removes_event_links_from_posts
    old_source = 'https://example.com/old'
    future_source = 'https://example.com/future'
    old_event_path = write_event('old-event', '2025-12-03T10:00:00-08:00', source_url: old_source)
    future_event_path = write_event('future-event', '2025-12-06T10:00:00-08:00', source_url: future_source)

    # Create posts that link to events - use actual event IDs
    post1 = write_post('post1', [old_event_path, future_event_path], source_url: old_source)
    post2 = write_post('post2', [future_event_path], source_url: future_source)

    @cleaner.run

    # Verify old event removed
    refute_path_exists old_event_path
    assert_path_exists future_event_path

    # Verify post1 only has future event link
    post1_doc = Mayhem::Models::News.find(post1.id)
    assert_equal [future_event_path], post1_doc.event_ids

    # Verify post2 still has its event link
    post2_doc = Mayhem::Models::News.find(post2.id)
    assert_equal [future_event_path], post2_doc.event_ids
  end

  private

  def write_event(name, start_date, end_date = nil, source_url: nil)
    front_matter = { 'title' => name, 'start_date' => start_date }
    front_matter['end_date'] = end_date if end_date
    front_matter['source_url'] = source_url if source_url
    event = Mayhem::Models::Event.create!(front_matter, body: '')
    event.path.to_s
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
