# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/events/stale_event_cleaner'
require 'mayhem/front_matter/document'

class StaleEventCleanerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('stale-events')
    @events_dir = File.join(@tmpdir, '_events')
    @posts_dir = File.join(@tmpdir, '_posts')
    FileUtils.mkdir_p(@events_dir)
    FileUtils.mkdir_p(@posts_dir)
    clock_time = Time.utc(2025, 12, 5, 19, 0, 0)
    @cleaner = Mayhem::Events::StaleEventCleaner.new(
      events_dir: @events_dir,
      posts_dir: @posts_dir,
      logger: Logger.new(IO::NULL),
      clock: -> { clock_time }
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
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
    event_path = File.join(@events_dir, 'missing-date.md')
    File.write(event_path, Mayhem::FrontMatter::Document.build_markdown({}, ''))

    @cleaner.run

    assert_path_exists event_path
  end

  def test_removes_event_links_from_posts
    old_event = write_event('old-event', '2025-12-03T10:00:00-08:00')
    future_event = write_event('future-event', '2025-12-06T10:00:00-08:00')

    # Create posts that link to events
    post1_path = write_post('post1', ['old-event', 'future-event'])
    post2_path = write_post('post2', ['old-event'])
    post3_path = write_post('post3', ['future-event'])

    @cleaner.run

    # Verify old event removed
    refute_path_exists old_event
    assert_path_exists future_event

    # Verify post1 only has future event link
    post1_doc = Mayhem::FrontMatter::Document.load(post1_path)
    assert_equal ['future-event'], post1_doc.front_matter['events']

    # Verify post2 has empty events array
    post2_doc = Mayhem::FrontMatter::Document.load(post2_path)
    assert_equal [], post2_doc.front_matter['events']

    # Verify post3 still has its event link
    post3_doc = Mayhem::FrontMatter::Document.load(post3_path)
    assert_equal ['future-event'], post3_doc.front_matter['events']
  end

  private

  def write_event(name, start_date, end_date = nil)
    front_matter = { 'start_date' => start_date }
    front_matter['end_date'] = end_date if end_date
    path = File.join(@events_dir, "#{name}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post(name, events)
    front_matter = {
      'title' => name,
      'date' => '2025-12-01T12:00:00-08:00',
      'events' => events
    }
    path = File.join(@posts_dir, "#{name}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end
end
