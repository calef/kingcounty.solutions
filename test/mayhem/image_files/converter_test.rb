# frozen_string_literal: true

require 'mini_magick'
require 'minitest/autorun'
require 'seldon'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/image_files/converter'

class ImageFilesConverterTest < Minitest::Test
  FakeImage = Struct.new(:width, :height, :blob) do
    def format(_); end

    def to_blob
      blob
    end
  end

  def setup
    @logger = Seldon::Logging.build_logger(env_var: 'LOG_LEVEL')
    @converter = Mayhem::ImageFiles::Converter.new()
  end

  def test_convert_to_webp_converts_raster_images
    fake_image = FakeImage.new(0, 0, 'webpdata')
    MiniMagick::Image.stub(:read, fake_image) do
      data, ext, converted = @converter.convert_to_webp('raw', '.jpg', 'https://example.com/img.jpg')
      assert_equal 'webpdata', data
      assert_equal '.webp', ext
      assert converted
    end
  end

  def test_convert_to_webp_handles_all_raster_formats
    fake_image = FakeImage.new(0, 0, 'webpdata')
    %w[.jpg .jpeg .png .gif .bmp .tif .tiff].each do |ext|
      MiniMagick::Image.stub(:read, fake_image) do
        data, result_ext, converted = @converter.convert_to_webp('raw', ext, 'https://example.com/img')
        assert_equal 'webpdata', data
        assert_equal '.webp', result_ext
        assert converted
      end
    end
  end

  def test_convert_to_webp_returns_original_for_non_raster_formats
    data, ext, converted = @converter.convert_to_webp('svg-data', '.svg', 'https://example.com/img.svg')
    assert_equal 'svg-data', data
    assert_equal '.svg', ext
    refute converted

    data, ext, converted = @converter.convert_to_webp('webp-data', '.webp', 'https://example.com/img.webp')
    assert_equal 'webp-data', data
    assert_equal '.webp', ext
    refute converted
  end

  def test_convert_to_webp_handles_conversion_errors
    MiniMagick::Image.stub(:read, proc { raise StandardError, 'conversion failed' }) do
      data, ext, converted = @converter.convert_to_webp('raw', '.jpg', 'https://example.com/img.jpg')
      assert_nil data
      assert_equal '.jpg', ext
      assert converted
    end
  end

  def test_convert_to_webp_handles_uppercase_extensions
    fake_image = FakeImage.new(0, 0, 'webpdata')
    MiniMagick::Image.stub(:read, fake_image) do
      data, ext, converted = @converter.convert_to_webp('raw', '.JPG', 'https://example.com/img.JPG')
      assert_equal 'webpdata', data
      assert_equal '.webp', ext
      assert converted
    end
  end
end
