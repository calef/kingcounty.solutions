# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'webmock/minitest'
require 'tmpdir'
require_relative '../../../lib/mayhem/images/extractor'
require_relative '../../../lib/mayhem/logging'

class ImageExtractorIntegrationTest < Minitest::Test
  def setup
    @original_min_dim = ENV['IMAGE_MIN_DIMENSION']
    ENV['IMAGE_MIN_DIMENSION'] = '0'
    @tmp_posts = Dir.mktmpdir
    @tmp_events = Dir.mktmpdir
    @tmp_images = Dir.mktmpdir
    @assets = Dir.mktmpdir

    # create a post with original_source_html containing an image
    fm = <<~MD
      ---
      title: Img Post
      date: #{Time.now.iso8601}
      source: Test
      source_url: https://example.com/p/1
      original_source_html: '<p>Image <img src="https://example.com/image.webp" alt="Example"></p>'
      summarized: true
      ---

      Body
    MD
    File.write(File.join(@tmp_posts, '2025-11-27-img-post.md'), fm)

    # stub image download
    VCR.use_cassette('content_image_extractor/image_download') do
      stub_request(:get, 'https://example.com/image.webp').to_return(status: 200, body: 'webpdata',
                                                                     headers: { 'Content-Type' => 'image/webp' })

      @extractor = Mayhem::Images::Extractor.new(posts_dir: @tmp_posts, events_dir: @tmp_events,
                                                              image_docs_dir: @tmp_images, asset_dir: @assets,
                                                              logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
                                                              min_dimension: 0)
    end
  end

  def teardown
    if @original_min_dim
      ENV['IMAGE_MIN_DIMENSION'] = @original_min_dim
    else
      ENV.delete('IMAGE_MIN_DIMENSION')
    end
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_events)
    FileUtils.remove_entry(@tmp_images)
    FileUtils.remove_entry(@assets)
  end

  def test_extract_downloads_and_creates_image_doc
    stats = @extractor.run

    assert_kind_of Hash, stats
    # ensure an _images doc was created
    files = Dir.glob(File.join(@tmp_images, '*.md'))

    assert_operator files.length, :>=, 1
  end
end
