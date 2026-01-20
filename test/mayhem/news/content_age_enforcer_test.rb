# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'mayhem/news/content_age_enforcer'
require 'mayhem/models/event'
require 'mayhem/models/image'
require 'mayhem/models/news'
require 'seldon'
require 'tmpdir'
require 'time'

class ContentAgeEnforcerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)
    @tmpdir = Mayhem::Models::News.repo.root.to_s
    @posts_dir = Mayhem::Models::News.collection_dir
    @images_dir = Mayhem::Models::Image.collection_dir
    @assets_dir = File.join(Mayhem::Models::Image.repo.root.to_s, 'assets', 'images')
    @events_dir = Mayhem::Models::Event.collection_dir
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@images_dir)
    FileUtils.mkdir_p(@assets_dir)
    FileUtils.mkdir_p(@events_dir)
    @config_path = File.join(@tmpdir, 'config.yml')
    @logger = Seldon::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @reference_time = Time.utc(2025, 12, 31)
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
    @images_repo_override.cleanup if @images_repo_override
  end

  def test_removes_old_posts_and_preserves_shared_images
    write_config(content_max_age_days: 30)
    shared_image = 'shared123'
    old_post_id = write_post('2025-01-01-old.md', 300, [shared_image])
    new_post_id = write_post('2025-12-01-new.md', 10, [shared_image])
    write_image_metadata(shared_image)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      config_path: @config_path,
      clock: -> { @reference_time }
    )

    enforcer.run

    assert_raises(FMRepo::NotFound, 'old post should be removed') { Mayhem::Models::News.find(old_post_id) }
    Mayhem::Models::News.find(new_post_id) # new post stays - no exception raised
    refute_nil Mayhem::Models::Image.find_by(checksum: shared_image), 'shared image metadata stays'
  end

  def test_removes_images_with_no_remaining_references
    write_config(content_max_age_days: 30)
    unique_image = 'unique123'
    write_image_metadata(unique_image)
    old_post_id = write_post('2025-01-01-old.md', 300, [unique_image])
    write_asset(unique_image)
    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      config_path: @config_path,
      clock: -> { @reference_time }
    )

    enforcer.run

    assert_raises(FMRepo::NotFound) { Mayhem::Models::News.find(old_post_id) }
    assert_nil Mayhem::Models::Image.find_by(checksum: unique_image)
    assert_empty Dir.glob(File.join(@assets_dir, "#{unique_image}.*"))
  end

  def test_removes_generated_events_when_post_removed
    write_config(content_max_age_days: 30)
    # Create events first to get their IDs
    event1_id = write_event('event1', generated: true)
    event2_id = write_event('event2', generated: false)

    # Create old post with event references
    old_post_id = write_post_with_event_ids(
      '2025-01-01-old.md',
      300,
      [event1_id, event2_id]
    )

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      config_path: @config_path,
      clock: -> { @reference_time }
    )

    enforcer.run

    # Post should be removed
    assert_raises(FMRepo::NotFound) { Mayhem::Models::News.find(old_post_id) }

    # Generated event should be removed
    assert_raises(FMRepo::NotFound) { Mayhem::Models::Event.find(event1_id) }

    # Non-generated event should remain
    Mayhem::Models::Event.find(event2_id) # no exception raised
  end

  def test_keeps_generated_events_with_remaining_post_references
    write_config(content_max_age_days: 30)
    # Create the shared generated event first
    shared_event_id = write_event('shared-event', generated: true)

    # Create two posts that reference the same event
    old_post_id = write_post_with_event_ids('2025-01-01-old.md', 300, [shared_event_id])
    new_post_id = write_post_with_event_ids('2025-12-01-new.md', 10, [shared_event_id])

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      config_path: @config_path,
      clock: -> { @reference_time }
    )

    enforcer.run

    # Old post should be removed
    assert_raises(FMRepo::NotFound) { Mayhem::Models::News.find(old_post_id) }

    # New post should remain
    Mayhem::Models::News.find(new_post_id) # no exception raised

    # Shared event should remain because new post still references it
    Mayhem::Models::Event.find(shared_event_id) # no exception raised
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
    post = Mayhem::Models::News.create!(front_matter, body: '')
    post.id
  end

  def write_post_with_event_ids(filename, days_ago, event_ids)
    date = @reference_time - (days_ago * 24 * 60 * 60)
    front_matter = {
      'date' => date.iso8601,
      'event_ids' => event_ids
    }
    post = Mayhem::Models::News.create!(front_matter, body: '')
    post.id
  end

  def write_event(id, generated:)
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => (@reference_time + 86_400).iso8601
    }
    front_matter['generated_from_post'] = true if generated
    event = Mayhem::Models::Event.create!(front_matter, body: '')
    event.id
  end

  def write_image_metadata(id)
    front_matter = {
      'checksum' => id,
      'image_url' => "/assets/images/#{id}.webp"
    }
    Mayhem::Models::Image.create!(front_matter, body: '')
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
