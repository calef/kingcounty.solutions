# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/news/pruner'
require 'mayhem/images/pruner'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

class NewsPrunerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('news-pruner')
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
    @pruner = Mayhem::News::Pruner.new(posts_dir: @posts_dir, images_pruner: @images_pruner, logger: @logger)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_unpublish_updates_front_matter_and_prunes_images
    image_id = 'shared-img'
    write_image_metadata(image_id)
    write_asset(image_id)
    post_path = write_post('post.md', [image_id])
    document = Mayhem::FrontMatter::Document.load(post_path)

    @pruner.unpublish(post_path, document)

    updated = Mayhem::FrontMatter::Document.load(post_path)
    refute updated.front_matter['published']
    assert_empty updated.front_matter['image_checksums']
    refute_path_exists File.join(@images_dir, "#{image_id}.md")
    assert_empty Dir.glob(File.join(@assets_dir, "#{image_id}.*"))
  end

  private

  def write_post(filename, image_checksums)
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'source_url' => 'https://example.com',
      'image_checksums' => image_checksums,
      'published' => true
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
