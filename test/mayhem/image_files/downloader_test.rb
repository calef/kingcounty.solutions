# frozen_string_literal: true

require_relative '../../test_helper'
require 'uri'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/image_files/downloader'
require_relative '../../../lib/mayhem/image_files/validator'
require_relative '../../../lib/mayhem/logging'

class ImageFilesDownloaderTest < Minitest::Test
  class DummyHttp
    attr_accessor :response

    def fetch(_url, accept:)
      response || raise(StandardError, 'no response configured')
    end
  end

  def setup
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    @validator = Mayhem::ImageFiles::Validator.new(logger: @logger, min_dimension: 300)
    @http = DummyHttp.new
    @downloader = Mayhem::ImageFiles::Downloader.new(
      logger: @logger,
      http_client: @http,
      validator: @validator
    )
  end

  def test_download_returns_nil_for_invalid_scheme
    stats = Hash.new(0)
    assert_nil @downloader.download('ftp://example.com/image.jpg', stats)
    assert_equal 0, stats[:download_failures]
  end

  def test_download_returns_nil_for_url_without_host
    stats = Hash.new(0)
    assert_nil @downloader.download('https://', stats)
    assert_equal 0, stats[:download_failures]
  end

  def test_download_skips_unsupported_extension
    stats = Hash.new(0)
    @http.response = { body: 'data', content_type: 'application/octet-stream' }

    assert_nil @downloader.download('https://example.com/file.bin', stats)
    assert_equal 1, stats[:skipped_unsupported_images]
  end

  def test_download_returns_body_when_allowed
    stats = Hash.new(0)
    @http.response = { body: 'image-data', content_type: 'image/jpeg' }

    result = @downloader.download('https://example.com/photo.jpg', stats)
    assert_equal 'image-data', result[:data]
    assert_equal '.jpg', result[:ext]
  end

  def test_download_handles_http_errors
    stats = Hash.new(0)
    @http.response = nil  # Will raise error

    result = @downloader.download('https://example.com/photo.jpg', stats)
    assert_nil result
    assert_equal 1, stats[:download_failures]
  end

  def test_download_detects_extension_from_path
    stats = Hash.new(0)
    @http.response = { body: 'data', content_type: 'image/jpeg' }

    result = @downloader.download('https://example.com/photo.png', stats)
    assert_equal 'data', result[:data]
    assert_equal '.png', result[:ext]
  end

  def test_download_detects_extension_from_content_type
    stats = Hash.new(0)
    @http.response = { body: 'data', content_type: 'image/gif' }

    result = @downloader.download('https://example.com/photo', stats)
    assert_equal 'data', result[:data]
    assert_equal '.gif', result[:ext]
  end
end
