# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/images/extractor'
require_relative '../../../lib/mayhem/models/image'

class ImageExtractorUnitTest < Minitest::Test
  class DummyHttp
    attr_accessor :response

    def fetch(_url, accept:)
      response || raise(StandardError, 'no response configured')
    end
  end

  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)
    @tmp_posts = Mayhem::Models::News.collection_dir
    @tmp_assets = Dir.mktmpdir('assets')
    @http = DummyHttp.new
    FileUtils.mkdir_p(@tmp_posts)
    @extractor = Mayhem::Images::Extractor.new(
      asset_dir: @tmp_assets,
      http_client: @http
    )
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @images_repo_override.cleanup if @images_repo_override
    FileUtils.remove_entry(@tmp_assets)
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

  def test_ensure_image_record_creates_front_matter
    frontmatter = { 'title' => 'Post', 'organization_title' => 'Test', 'date' => '2025-01-01' }
    checksum = 'deadbeef'
    filename = 'deadbeef.webp'
    original_url = 'https://example.com/img.png'

    @extractor.send(:ensure_image_record, checksum, 'Alt', filename, frontmatter, original_url)

    image = Mayhem::Models::Image.find_by(checksum: checksum)
    assert_equal checksum, image.checksum
    assert_match(%r{/#{Regexp.escape(filename)}\z}, image.image_url)
    assert_equal original_url, image.source_url
    assert_equal 'Alt', image.title
    assert_equal frontmatter['organization_title'], image.organization_title
  end

  def test_ensure_image_record_prefers_start_date_when_date_missing
    frontmatter = {
      'title' => 'Event',
      'organization_title' => 'Test Org',
      'start_date' => '2026-01-15T16:00:00-08:00'
    }
    checksum = 'cafebabe'
    filename = 'cafebabe.webp'
    original_url = 'https://example.com/banner.png'

    @extractor.send(:ensure_image_record, checksum, 'Banner', filename, frontmatter, original_url)

    image = Mayhem::Models::Image.find_by(checksum: checksum)
    assert_equal frontmatter['start_date'], image.date
  end

  def test_ensure_image_record_falls_back_to_now_when_date_missing
    frontmatter = { 'title' => 'No Date', 'organization_title' => 'Test Org' }
    checksum = 'beadfeed'
    filename = 'beadfeed.webp'
    original_url = 'https://example.com/no-date.png'

    @extractor.send(:ensure_image_record, checksum, 'Alt', filename, frontmatter, original_url)

    image = Mayhem::Models::Image.find_by(checksum: checksum)
    Time.iso8601(image.date)
  end

  def test_run_skips_unsummarized_posts
    fm = <<~MD
      ---
      title: Unsummarized Post
      date: 2025-01-01
      organization_title: Test
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
