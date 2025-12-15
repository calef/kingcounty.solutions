# frozen_string_literal: true

require 'mini_magick'
require_relative 'validator'

module Mayhem
  module ImageFiles
    class Converter
      attr_reader :logger

      def initialize(logger:)
        @logger = logger
      end

      def convert_to_webp(data, ext, source_url)
        ext = ext.to_s.downcase
        return [data, ext] unless Validator::RASTER_EXTENSIONS.include?(ext)

        image = MiniMagick::Image.read(data)
        image.format 'webp'
        [image.to_blob, '.webp']
      rescue StandardError => e
        logger.warn "Failed to convert #{source_url} to WebP: #{e.message}"
        [data, ext]
      end
    end
  end
end
