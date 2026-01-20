# frozen_string_literal: true

require 'pathname'
require_relative '../test_helper'
require_relative '../../lib/mayhem/models/image'

class ImageWebPTest < Minitest::Test
  ASSET_DIR = File.join('assets', 'images')
  LOCAL_PREFIX = '/assets/images/'
  PERMITTED_EXTENSIONS = %w[.webp .svg].freeze

  def test_asset_files_are_webp
    errors = Dir[File.join(ASSET_DIR, '*.*')].filter_map do |path|
      next if PERMITTED_EXTENSIONS.include?(File.extname(path).downcase)

      "#{path}: expected WebP or SVG asset filename"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_image_documents_reference_webp_assets
    errors = Mayhem::Models::Image.all.filter_map do |image|
      image_url = image['image_url']
      next unless image_url.is_a?(String) && image_url.start_with?(LOCAL_PREFIX)

      relative_path = image_url.sub(%r{\A/+}, '')
      asset_path = Pathname.new(relative_path).cleanpath
      asset_path = Pathname.pwd.join(asset_path) unless asset_path.absolute?
      next "#{image.id}: referenced asset #{image_url} does not exist" unless asset_path.file?

      next if PERMITTED_EXTENSIONS.include?(asset_path.extname.downcase)

      "#{image.id}: image_url #{image_url} must reference a WebP or SVG asset"
    end

    assert_empty errors, errors.join("\n")
  end
end
