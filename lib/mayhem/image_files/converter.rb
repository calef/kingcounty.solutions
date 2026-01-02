# frozen_string_literal: true

require 'mini_magick'
require 'seldon'
require_relative 'validator'

module Mayhem
  module ImageFiles
    class Converter
      include Seldon::Loggable

      def convert_to_webp(data, ext, source_url)
        ext = ext.to_s.downcase
        raster = Validator::RASTER_EXTENSIONS.include?(ext)
        return [data, ext, false] unless raster

        image = MiniMagick::Image.read(data)
        image.format 'webp'
        [image.to_blob, '.webp', true]
      rescue StandardError => e
        logger.warn "Failed to convert #{source_url} to WebP: #{e.message}"
        [nil, ext, true]
      end
    end
  end
end
