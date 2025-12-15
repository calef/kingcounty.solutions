# frozen_string_literal: true

require_relative '../../test_helper'
require 'mini_magick'
require 'uri'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/image_files/validator'
require_relative '../../../lib/mayhem/logging'

class ImageFilesValidatorTest < Minitest::Test
  FakeImage = Struct.new(:width, :height)

  def setup
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    @validator = Mayhem::ImageFiles::Validator.new(logger: @logger, min_dimension: 300)
  end

  def test_allowed_extension_returns_true_for_valid_extensions
    assert @validator.allowed_extension?('.jpg')
    assert @validator.allowed_extension?('.jpeg')
    assert @validator.allowed_extension?('.png')
    assert @validator.allowed_extension?('.gif')
    assert @validator.allowed_extension?('.webp')
    assert @validator.allowed_extension?('.svg')
  end

  def test_allowed_extension_returns_false_for_invalid_extensions
    refute @validator.allowed_extension?('.exe')
    refute @validator.allowed_extension?('.txt')
    refute @validator.allowed_extension?('.bin')
    refute @validator.allowed_extension?(nil)
  end

  def test_image_extension_prefers_path_extension
    uri = URI('https://example.com/picture.png')
    assert_equal '.png', @validator.image_extension(uri, 'image/jpeg')
  end

  def test_image_extension_falls_back_to_content_type
    uri = URI('https://example.com/image')
    assert_equal '.jpg', @validator.image_extension(uri, 'image/jpeg')
    assert_equal '.png', @validator.image_extension(uri, 'image/png')
    assert_equal '.gif', @validator.image_extension(uri, 'image/gif')
    assert_equal '.webp', @validator.image_extension(uri, 'image/webp')
  end

  def test_image_extension_handles_content_type_with_charset
    uri = URI('https://example.com/image')
    assert_equal '.jpg', @validator.image_extension(uri, 'image/jpeg; charset=utf-8')
  end

  def test_meets_minimum_dimensions_returns_true_for_large_images
    stats = Hash.new(0)
    good_image = FakeImage.new(400, 400)
    MiniMagick::Image.stub(:read, good_image) do
      assert @validator.meets_minimum_dimensions?('data', 'https://example.com/img.jpg', stats)
    end
    assert_equal 0, stats[:skipped_small_images]
  end

  def test_meets_minimum_dimensions_returns_false_for_small_images
    stats = Hash.new(0)
    small_image = FakeImage.new(100, 100)
    MiniMagick::Image.stub(:read, small_image) do
      refute @validator.meets_minimum_dimensions?('data', 'https://example.com/img.jpg', stats)
    end
    assert_equal 1, stats[:skipped_small_images]
  end

  def test_meets_minimum_dimensions_handles_minimagick_errors
    stats = Hash.new(0)
    MiniMagick::Image.stub(:read, proc { raise MiniMagick::Error, 'fail' }) do
      refute @validator.meets_minimum_dimensions?('data', 'https://example.com/img.jpg', stats)
    end
    assert_equal 1, stats[:skipped_small_images]
  end

  def test_meets_minimum_dimensions_returns_true_when_min_dimension_is_zero
    validator = Mayhem::ImageFiles::Validator.new(logger: @logger, min_dimension: 0)
    stats = Hash.new(0)
    assert validator.meets_minimum_dimensions?('data', 'https://example.com/img.jpg', stats)
    assert_equal 0, stats[:skipped_small_images]
  end
end
