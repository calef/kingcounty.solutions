# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'tmpdir'
require 'test_helper'
require 'mayhem/support/content_pruner'
require 'mayhem/support/front_matter_document'
require 'mayhem/logging'

class ContentPrunerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('content-pruner-test')
    @posts_dir = File.join(@tmpdir, '_posts')
    @images_dir = File.join(@tmpdir, '_images')
    @assets_dir = File.join(@tmpdir, 'assets', 'images')
    @events_dir = File.join(@tmpdir, '_events')
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@images_dir)
    FileUtils.mkdir_p(@assets_dir)
    FileUtils.mkdir_p(@events_dir)
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @pruner = Mayhem::Support::ContentPruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      logger: @logger
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_unpublish_post_updates_front_matter_and_removes_images
    image_id = 'shared-img'
    write_image_metadata(image_id)
    write_asset(image_id)
    post_path = write_post('post.md', 'https://example.com', [image_id], true)
    document = Mayhem::Support::FrontMatterDocument.load(post_path)

    @pruner.unpublish_post(post_path, document)

    updated = Mayhem::Support::FrontMatterDocument.load(post_path)
    refute updated.front_matter['published']
    assert_empty updated.front_matter['images']
    refute_path_exists File.join(@images_dir, "#{image_id}.md")
  end

  def test_delete_event_removes_file_and_cleans_posts
    event_path = write_event('event-1')
    post_path = write_post('post.md', 'https://example.com', [], true, ['event-1'])

    @pruner.delete_event(event_path)

    refute_path_exists event_path
    updated = Mayhem::Support::FrontMatterDocument.load(post_path)
    assert_empty updated.front_matter['events']
  end

  private

  def write_post(filename, source_url, images, published, events = [])
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'source_url' => source_url,
      'images' => images,
      'events' => events,
      'published' => published
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, ''))
    path
  end

  def write_event(id)
    path = File.join(@events_dir, "#{id}.md")
    content = Mayhem::Support::FrontMatterDocument.build_markdown(
      { 'title' => "Event #{id}", 'start_date' => Time.now.utc.iso8601 },
      ''
    )
    File.write(path, content)
    path
  end

  def write_image_metadata(id)
    File.write(File.join(@images_dir, "#{id}.md"), "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
