# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'webmock/minitest'
require 'tmpdir'
require_relative '../../lib/mayhem/news/post_image_extractor'
require_relative '../../lib/mayhem/logging'

class PostImageExtractorTest < Minitest::Test
  def setup
    @tmp_posts = Dir.mktmpdir
    @tmp_images = Dir.mktmpdir
    @assets = Dir.mktmpdir

    # create a post with original_markdown_body containing an image
    fm = <<~MD
      ---
      title: Img Post
      date: #{Time.now.iso8601}
      source: Test
      source_url: https://example.com/p/1
      original_markdown_body: '![](https://example.com/image.jpg)'
      summarized: true
      ---

      Body
    MD
    File.write(File.join(@tmp_posts, '2025-11-27-img-post.md'), fm)

    # stub image download
    if !defined?(WebMock) || WebMock.nil?
      skip 'WebMock not available; skipping network-dependent test'
    end

    stub_request(:get, 'https://example.com/image.jpg').to_return(status: 200, body: File.binread(__FILE__), headers: { 'Content-Type' => 'image/jpeg' })

    @extractor = Mayhem::News::PostImageExtractor.new(posts_dir: @tmp_posts, image_docs_dir: @tmp_images, asset_dir: @assets, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_images)
    FileUtils.remove_entry(@assets)
  end

  def test_extract_downloads_and_creates_image_doc
    stats = @extractor.run
    assert_kind_of Hash, stats
    # ensure an _images doc was created
    files = Dir.glob(File.join(@tmp_images, '*.md'))
    assert files.length >= 1
  end
end
