# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'tmpdir'
require 'test_helper'
require 'mayhem/events/stale_event_cleaner'
require 'mayhem/support/front_matter_document'

class StaleEventCleanerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('stale-events')
    @events_dir = File.join(@tmpdir, '_events')
    FileUtils.mkdir_p(@events_dir)
    clock_time = Time.utc(2025, 12, 5, 19, 0, 0)
    @cleaner = Mayhem::Events::StaleEventCleaner.new(
      events_dir: @events_dir,
      logger: Logger.new(IO::NULL),
      clock: -> { clock_time }
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_removes_events_scheduled_before_now
    old_event = write_event('old-event', '2025-12-04T10:00:00-08:00')
    early_today = write_event('early-today', '2025-12-05T10:30:00-08:00')
    upcoming_today = write_event('upcoming-today', '2025-12-05T12:30:00-08:00')
    future_event = write_event('future-event', '2025-12-06T10:00:00-08:00')

    @cleaner.run

    refute_path_exists old_event
    refute_path_exists early_today
    assert_path_exists upcoming_today
    assert_path_exists future_event
  end

  def test_skips_events_with_missing_start_date
    event_path = File.join(@events_dir, 'missing-date.md')
    File.write(event_path, Mayhem::Support::FrontMatterDocument.build_markdown({}, ''))

    @cleaner.run

    assert_path_exists event_path
  end

  private

  def write_event(name, start_date)
    front_matter = { 'start_date' => start_date }
    path = File.join(@events_dir, "#{name}.md")
    File.write(path, Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, ''))
    path
  end
end
