# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'time'
require 'test_helper'
require 'mayhem/news/content_age_enforcer'
require 'mayhem/support/front_matter_document'
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

  private

  def write_config(options = {})
    config = { 'content_max_age_days' => options[:content_max_age_days] }
    File.write(@config_path, config.to_yaml)
  end

  def write_post(filename, days_ago, images)
    date = @reference_time - (days_ago * 24 * 60 * 60)
    front_matter = {
      'date' => date.iso8601,
      'images' => images
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, ''))
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
