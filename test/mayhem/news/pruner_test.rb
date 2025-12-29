# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/news/pruner'
require 'mayhem/images/pruner'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

class NewsPrunerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)
    @posts_dir = Mayhem::Models::News.collection_dir
    @events_dir = Mayhem::Models::Event.collection_dir
    @images_dir = Mayhem::Models::Image.collection_dir
    @assets_dir = Dir.mktmpdir('assets')
    FileUtils.mkdir_p([@posts_dir, @events_dir, @images_dir, @assets_dir])
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @images_pruner = Mayhem::Images::Pruner.new(
      images_dir: @images_dir,
      assets_dir: @assets_dir
    )
    @pruner = Mayhem::News::Pruner.new(images_pruner: @images_pruner)
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
    @images_repo_override.cleanup if @images_repo_override
    FileUtils.remove_entry(@assets_dir) if @assets_dir && File.exist?(@assets_dir)
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
