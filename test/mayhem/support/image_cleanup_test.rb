# frozen_string_literal: true

require 'fileutils'
require 'set'
require 'tmpdir'
require 'time'
require 'test_helper'
require 'mayhem/support/image_cleanup'
require 'mayhem/support/front_matter_document'
require 'mayhem/logging'

class ImageCleanupTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('image-cleanup-test')
    @posts_dir = File.join(@tmpdir, '_posts')
    @images_dir = File.join(@tmpdir, '_images')
    @assets_dir = File.join(@tmpdir, 'assets', 'images')
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@images_dir)
    FileUtils.mkdir_p(@assets_dir)
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
    @cleanup = Mayhem::Support::ImageCleanup.new(
      posts_dir: @posts_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      logger: @logger
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_collect_image_ids_handles_missing_values
    front_matter = { 'images' => ['foo', nil, '  bar '] }

    assert_equal %w[foo bar], @cleanup.collect_image_ids(front_matter)
  end

  def test_remaining_image_counts_excludes_path
    post_a = write_post('a.md', %w[id1 id2])
    write_post('b.md', %w[id2])

    counts = @cleanup.remaining_image_counts(Set[post_a])

    assert_equal 1, counts['id2']
    refute counts.key?('id1')
  end

  def test_cleanup_removes_unreferenced_images
    post_path = write_post('post.md', %w[id-rm])
    write_image_metadata('id-rm')
    write_asset('id-rm')

    removed = @cleanup.cleanup(%w[id-rm], excluded_paths: Set[post_path])

    assert_equal ['id-rm'], removed
    refute_path_exists File.join(@images_dir, 'id-rm.md')
    assert_empty Dir.glob(File.join(@assets_dir, 'id-rm.*'))
  end

  private

  def write_post(filename, images)
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'images' => images,
      'source_url' => 'https://example.com'
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, ''))
    path
  end

  def write_image_metadata(id)
    File.write(File.join(@images_dir, "#{id}.md"), "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
