# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/images/extractor'

class ImageExtractorUnitTest < Minitest::Test
  class DummyHttp
    attr_accessor :response

    def fetch(_url, accept:, max_bytes:)
      response || raise(StandardError, 'no response configured')
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
    assert_equal frontmatter['source'], doc.front_matter['organization_title']
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
