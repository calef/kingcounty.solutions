# frozen_string_literal: true

require 'mini_magick'
require_relative 'test_helper'

class ImageDimensionTest < Minitest::Test
  MIN_DIMENSION = 300

  def test_webp_assets_meet_minimum_dimensions
    images = Dir[File.join('assets', 'images', '*.webp')]
    skip 'No WebP assets to validate' if images.empty?

    errors = images.filter_map do |path|
      image = MiniMagick::Image.open(path)
      next if image.width >= MIN_DIMENSION && image.height >= MIN_DIMENSION

      "#{path}: dimensions #{image.width}x#{image.height} are smaller than #{MIN_DIMENSION}"
    rescue MiniMagick::Error => e
      "#{path}: unable to read dimensions (#{e.message})"
    end

    assert errors.empty?, errors.join("\n")
  end
end
