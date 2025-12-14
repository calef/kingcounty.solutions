# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'mini_magick'
require 'uri'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/images/extractor'

class ImageExtractorUnitTest < Minitest::Test
  class DummyHttp
    attr_accessor :response

    def fetch(_url, accept:, max_bytes:)
      response || raise(StandardError, 'no response configured')
    end
  end

  FakeImage = Struct.new(:width, :height, :blob) do
    def format(_); end

    def to_blob
      blob
    end
  end

  def setup
    @tmp_posts = Dir.mktmpdir('posts')
    @tmp_assets = Dir.mktmpdir('assets')
    @tmp_images = Dir.mktmpdir('images')
    @http = DummyHttp.new
    @extractor = Mayhem::Images::Extractor.new(
      posts_dir: @tmp_posts,
      events_dir: nil,
      image_docs_dir: @tmp_images,
      asset_dir: @tmp_assets,
      logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
      http_client: @http
    )
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_assets)
    FileUtils.remove_entry(@tmp_images)
  end

  def test_extract_images_from_markdown_and_html
    markdown = <<~MD
      ![alt text](https://example.com/pic.jpg "Title")
      <img src="https://example.org/embed.png" alt="embedded">
    MD

    images = @extractor.send(:extract_images, markdown)
    assert_equal 2, images.length
    assert_equal 'https://example.com/pic.jpg', images.first[:url]
    assert_equal 'embedded', images.last[:alt]
  end

  def test_download_image_returns_nil_for_invalid_scheme
    stats = Hash.new(0)
    assert_nil @extractor.send(:download_image, 'ftp://example.com/image.jpg', stats)
    assert_equal 0, stats[:download_failures]
  end

  def test_download_image_skips_unsupported_extension
    stats = Hash.new(0)
    @http.response = { body: 'data', content_type: 'application/octet-stream' }

    assert_nil @extractor.send(:download_image, 'https://example.com/file.bin', stats)
    assert_equal 1, stats[:skipped_unsupported_images]
  end

  def test_download_image_returns_body_when_allowed
    stats = Hash.new(0)
    @http.response = { body: 'data', content_type: 'image/jpeg' }

    result = @extractor.send(:download_image, 'https://example.com/photo.jpg', stats)
    assert_equal 'data', result[:data]
    assert_equal '.jpg', result[:ext]
  end

  def test_image_extension_prefers_path_then_content_type
    uri = URI('https://example.com/picture.png')
    assert_equal '.png', @extractor.send(:image_extension, uri, 'image/jpeg')

    uri = URI('https://example.com/image')
    assert_equal '.jpg', @extractor.send(:image_extension, uri, 'image/jpeg; charset=utf-8')
  end

  def test_allowed_extension_returns_boolean
    assert @extractor.send(:allowed_extension?, '.jpg')
    refute @extractor.send(:allowed_extension?, '.exe')
  end

  def test_convert_to_webp_for_raster_images
    fake_image = FakeImage.new(0, 0, 'webpdata')
    MiniMagick::Image.stub(:read, fake_image) do
      data, ext = @extractor.send(:convert_to_webp, 'raw', '.jpg', 'url')
      assert_equal 'webpdata', data
      assert_equal '.webp', ext
    end
  end

  def test_convert_to_webp_returns_original_on_error
    MiniMagick::Image.stub(:read, proc { raise StandardError, 'broken' }) do
      data, ext = @extractor.send(:convert_to_webp, 'raw', '.jpg', 'url')
      assert_equal 'raw', data
      assert_equal '.jpg', ext
    end
  end

  def test_meets_minimum_dimensions_true_and_false
    stats = Hash.new(0)
    good_image = FakeImage.new(400, 400, 'data')
    MiniMagick::Image.stub(:read, good_image) do
      assert @extractor.send(:meets_minimum_dimensions?, 'data', 'url', stats)
    end

    small_image = FakeImage.new(100, 100, 'data')
    stats.clear
    MiniMagick::Image.stub(:read, small_image) do
      refute @extractor.send(:meets_minimum_dimensions?, 'data', 'url', stats)
      assert_equal 1, stats[:skipped_small_images]
    end
  end

  def test_meets_minimum_dimensions_handles_error
    stats = Hash.new(0)
    MiniMagick::Image.stub(:read, proc { raise MiniMagick::Error, 'fail' }) do
      refute @extractor.send(:meets_minimum_dimensions?, 'data', 'url', stats)
      assert_equal 1, stats[:skipped_small_images]
    end
  end

  def test_image_asset_filename_writes_file
    filename = @extractor.send(:image_asset_filename, 'abc', '.webp') { 'bytes' }
    assert_equal 'abc.webp', filename
    assert File.exist?(File.join(@tmp_assets, filename))
  end

  def test_ensure_image_doc_creates_front_matter
    frontmatter = { 'title' => 'Post', 'source' => 'Test', 'date' => '2025-01-01' }
    checksum = 'deadbeef'
    filename = 'deadbeef.webp'
    original_url = 'https://example.com/img.png'

    @extractor.send(:ensure_image_doc, checksum, 'Alt', filename, frontmatter, original_url)

    doc = Mayhem::FrontMatter::Document.load(File.join(@tmp_images, "#{checksum}.md"))
    assert_equal checksum, doc.front_matter['checksum']
    assert_match(%r{/#{Regexp.escape(filename)}\z}, doc.front_matter['image_url'])
    assert_equal original_url, doc.front_matter['source_url']
    assert_equal 'Alt', doc.front_matter['title']
    assert_equal frontmatter['source'], doc.front_matter['source']
  end

  def test_run_skips_unsummarized_posts
    fm = <<~MD
      ---
      title: Unsummarized Post
      date: 2025-01-01
      source: Test
      source_url: https://example.com/unsummarized
      original_source_html: '![](https://example.com/image.jpg)'
      summarized: false
      ---

      Body
    MD
    File.write(File.join(@tmp_posts, '2025-01-01-unsummarized.md'), fm)

    stats = @extractor.run

    assert_equal 1, stats[:skipped_unsummarized]
    assert_equal 0, stats[:posts_updated]
  end
end
