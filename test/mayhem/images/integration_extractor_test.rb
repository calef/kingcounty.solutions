# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'seldon'
require 'tmpdir'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/images/extractor'
require_relative '../../../lib/mayhem/models/image'
require_relative '../../../lib/mayhem/models/news'

class ImageExtractorIntegrationTest < Minitest::Test
  def setup
    @original_min_dim = ENV['IMAGE_MIN_DIMENSION']
    ENV['IMAGE_MIN_DIMENSION'] = '0'
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)
    @tmp_posts = Mayhem::Models::News.collection_dir
    @assets = Mayhem::Models::Image.repo.root.to_s
    FileUtils.mkdir_p(@tmp_posts)
    @assets_images = File.join(@assets, 'assets', 'images')
    FileUtils.mkdir_p(@assets_images)

    # create a post with original_source_html containing an image
    post = Mayhem::Models::News.create!(
      {
        'title' => 'Img Post',
        'date' => Time.now.iso8601,
        'source' => 'Test',
        'source_url' => 'https://example.com/p/1',
        'original_source_html' => '<p>Image <img src="https://example.com/image.webp" alt="Example"></p>',
        'summarized' => true
      },
      body: 'Body'
    )

    # stub image download
    VCR.use_cassette('content_image_extractor/image_download') do
      stub_request(:get, 'https://example.com/image.webp').to_return(status: 200, body: 'webpdata',
                                                                     headers: { 'Content-Type' => 'image/webp' })

      @extractor = Mayhem::Images::Extractor.new(
        asset_dir: @assets_images,
        min_dimension: 0
      )
    end
  end

  def teardown
    if @original_min_dim
      ENV['IMAGE_MIN_DIMENSION'] = @original_min_dim
    else
      ENV.delete('IMAGE_MIN_DIMENSION')
    end
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
    @images_repo_override.cleanup if @images_repo_override
  end

  def test_extract_downloads_and_creates_image_doc
    stats = @extractor.run

    assert_kind_of Hash, stats
    # ensure an image record was created
    images = Mayhem::Models::Image.all.to_a

    assert_operator images.length, :>=, 1
  end
end
