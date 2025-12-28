# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/events/pruner'
require 'mayhem/images/pruner'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

class EventsPrunerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('events-pruner')
    @posts_dir = File.join(@tmpdir, '_posts')
    @events_dir = File.join(@tmpdir, '_events')
    @images_dir = File.join(@tmpdir, '_images')
    @assets_dir = File.join(@tmpdir, 'assets', 'images')
    FileUtils.mkdir_p([@posts_dir, @events_dir, @images_dir, @assets_dir])
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @images_pruner = Mayhem::Images::Pruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      logger: @logger
    )
    @pruner = Mayhem::Events::Pruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_pruner: @images_pruner,
      logger: @logger
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_delete_removes_file_and_cleans_post_references
    event_path = write_event('event-1')
    write_post('post.md', ['event-1.md'])

    @pruner.delete(event_path)

    refute_path_exists event_path
    updated = Mayhem::FrontMatter::Document.load(File.join(@posts_dir, 'post.md'))
    assert_empty updated.front_matter['event_ids']
  end

  def test_unpublish_removes_images
    image_id = 'event-img'
    write_image_metadata(image_id)
    write_asset(image_id)
    event_path = write_event('event-2', image_checksums: [image_id])
    document = Mayhem::FrontMatter::Document.load(event_path)

    @pruner.unpublish(event_path, document)

    updated = Mayhem::FrontMatter::Document.load(event_path)
    refute updated.front_matter['published']
    assert_empty updated.front_matter['image_checksums']
    refute_path_exists File.join(@images_dir, "#{image_id}.md")
    assert_empty Dir.glob(File.join(@assets_dir, "#{image_id}.*"))
  end

  private

  def write_event(id, image_checksums: [])
    path = File.join(@events_dir, "#{id}.md")
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => Time.now.utc.iso8601,
      'image_checksums' => image_checksums,
      'published' => true
    }
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post(filename, event_ids)
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'source_url' => 'https://example.com',
      'event_ids' => event_ids
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_image_metadata(id)
    File.write(File.join(@images_dir, "#{id}.md"), "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
