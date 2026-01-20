# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'mayhem/news/content_age_enforcer'
require 'mayhem/front_matter/document'
require 'seldon'
require 'tmpdir'
require 'time'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

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
    old_post = write_post('2025-01-01-old.md', 300, [shared_image])
    new_post = write_post('2025-12-01-new.md', 10, [shared_image])
    write_image_metadata(shared_image)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      assets_dir: @assets_dir,
      config_path: @config_path,
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
      assets_dir: @assets_dir,
      config_path: @config_path,
      clock: -> { @reference_time }
    )

    enforcer.run

    refute_path_exists old_post
    refute_path_exists File.join(@images_dir, "#{unique_image}.md")
    assert_empty Dir.glob(File.join(@assets_dir, "#{unique_image}.*"))
  end

  def test_removes_generated_events_when_post_removed
    write_config(content_max_age_days: 30)
    # Create old post with event references
    old_post = write_post_with_event_ids(
      '2025-01-01-old.md',
      300,
      [event_id_for('event1'), event_id_for('event2')]
    )

    # Create the events (one generated, one not)
    event1 = write_event(@events_dir, 'event1', generated: true)
    event2 = write_event(@events_dir, 'event2', generated: false)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      assets_dir: @assets_dir,
      config_path: @config_path,
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
    # Create two posts that reference the same event
    shared_event_id = event_id_for('shared-event')
    old_post = write_post_with_event_ids('2025-01-01-old.md', 300, [shared_event_id])
    new_post = write_post_with_event_ids('2025-12-01-new.md', 10, [shared_event_id])

    # Create the shared generated event
    shared_event = write_event(@events_dir, 'shared-event', generated: true)

    enforcer = Mayhem::News::ContentAgeEnforcer.new(
      assets_dir: @assets_dir,
      config_path: @config_path,
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

  def write_post_with_event_ids(filename, days_ago, event_ids)
    date = @reference_time - (days_ago * 24 * 60 * 60)
    front_matter = {
      'date' => date.iso8601,
      'event_ids' => event_ids
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def event_id_for(id)
    File.join('_events', "#{id}.md")
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
    content = <<~YAML
      ---
      checksum: #{id}
      image_url: "/assets/images/#{id}.webp"
      ---
    YAML
    File.write(path, content)
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
