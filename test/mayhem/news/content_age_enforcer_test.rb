# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'time'
require_relative '../../test_helper'
require 'mayhem/news/content_age_enforcer'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

class ContentAgeEnforcerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('content-age')
    @posts_dir = File.join(@tmpdir, '_posts')
    @images_dir = File.join(@tmpdir, '_images')
    @assets_dir = File.join(@tmpdir, 'assets', 'images')
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@images_dir)
    FileUtils.mkdir_p(@assets_dir)
    @config_path = File.join(@tmpdir, 'config.yml')
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @reference_time = Time.utc(2025, 12, 31)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_removes_old_posts_and_preserves_shared_images
    write_config(content_max_age_days: 30)
    shared_image = 'shared123'
    old_post = write_post('2025-01-01-old.md', 300, [shared_image])
    new_post = write_post('2025-12-01-new.md', 10, [shared_image])
    write_image_metadata(shared_image)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      posts_dir: @posts_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      config_path: @config_path,
      logger: @logger,
      clock: -> { @reference_time }
    )

    enforcer.run

    refute_path_exists old_post, 'old post should be removed'
    assert_path_exists new_post, 'new post stays'
    assert_path_exists File.join(@images_dir, "#{shared_image}.md"), 'shared image metadata stays'
  end

  def test_removes_images_with_no_remaining_references
    write_config(content_max_age_days: 30)
    unique_image = 'unique123'
    write_image_metadata(unique_image)
    old_post = write_post('2025-01-01-old.md', 300, [unique_image])
    write_asset(unique_image)
    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      posts_dir: @posts_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      config_path: @config_path,
      logger: @logger,
      clock: -> { @reference_time }
    )

    enforcer.run

    refute_path_exists old_post
    refute_path_exists File.join(@images_dir, "#{unique_image}.md")
    assert_empty Dir.glob(File.join(@assets_dir, "#{unique_image}.*"))
  end

  def test_removes_generated_events_when_post_removed
    write_config(content_max_age_days: 30)
    events_dir = File.join(@tmpdir, '_events')
    FileUtils.mkdir_p(events_dir)

    # Create old post with event references
    old_post = write_post_with_events('2025-01-01-old.md', 300, %w[event1 event2])

    # Create the events (one generated, one not)
    event1 = write_event(events_dir, 'event1', generated: true)
    event2 = write_event(events_dir, 'event2', generated: false)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      posts_dir: @posts_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      events_dir: events_dir,
      config_path: @config_path,
      logger: @logger,
      clock: -> { @reference_time }
    )

    enforcer.run

    # Post should be removed
    refute_path_exists old_post

    # Generated event should be removed
    refute_path_exists event1

    # Non-generated event should remain
    assert_path_exists event2
  end

  def test_keeps_generated_events_with_remaining_post_references
    write_config(content_max_age_days: 30)
    events_dir = File.join(@tmpdir, '_events')
    FileUtils.mkdir_p(events_dir)

    # Create two posts that reference the same event
    old_post = write_post_with_events('2025-01-01-old.md', 300, ['shared-event'])
    new_post = write_post_with_events('2025-12-01-new.md', 10, ['shared-event'])

    # Create the shared generated event
    shared_event = write_event(events_dir, 'shared-event', generated: true)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      posts_dir: @posts_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      events_dir: events_dir,
      config_path: @config_path,
      logger: @logger,
      clock: -> { @reference_time }
    )

    enforcer.run

    # Old post should be removed
    refute_path_exists old_post

    # New post should remain
    assert_path_exists new_post

    # Shared event should remain because new post still references it
    assert_path_exists shared_event
  end

  private

  def write_config(options = {})
    config = { 'content_max_age_days' => options[:content_max_age_days] }
    File.write(@config_path, config.to_yaml)
  end

  def write_post(filename, days_ago, image_checksums)
    date = @reference_time - (days_ago * 24 * 60 * 60)
    front_matter = {
      'date' => date.iso8601,
      'image_checksums' => image_checksums
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post_with_events(filename, days_ago, events)
    date = @reference_time - (days_ago * 24 * 60 * 60)
    front_matter = {
      'date' => date.iso8601,
      'events' => events
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_event(events_dir, id, generated:)
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => (@reference_time + 86_400).iso8601
    }
    front_matter['generated_from_post'] = true if generated
    path = File.join(events_dir, "#{id}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_image_metadata(id)
    path = File.join(@images_dir, "#{id}.md")
    File.write(path, "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
