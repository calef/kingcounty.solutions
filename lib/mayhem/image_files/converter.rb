# frozen_string_literal: true

require 'mini_magick'

module Mayhem
  module ImageFiles
    class Converter
      RASTER_EXTENSIONS = %w[.jpg .jpeg .png .gif .bmp .tif .tiff].freeze

      attr_reader :logger

      def initialize(logger:)
        @logger = logger
      end

      def convert_to_webp(data, ext, source_url)
        ext = ext.to_s.downcase
        return [data, ext] unless RASTER_EXTENSIONS.include?(ext)

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
