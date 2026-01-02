# frozen_string_literal: true

require 'mini_magick'
require 'seldon'

module Mayhem
  module ImageFiles
    class Validator
      include Seldon::Loggable

      RASTER_EXTENSIONS = %w[.jpg .jpeg .png .gif .bmp .tif .tiff].freeze
      ALLOWED_EXTENSIONS = (RASTER_EXTENSIONS + %w[.webp .svg]).freeze
      CONTENT_TYPE_TO_EXTENSION = {
        'image/jpeg' => '.jpg',
        'image/png' => '.png',
        'image/gif' => '.gif',
        'image/webp' => '.webp',
        'image/svg+xml' => '.svg'
      }.freeze

      attr_reader :min_dimension

      def initialize(min_dimension: 300)
        @min_dimension = min_dimension
      end

      def allowed_extension?(extension)
        extension && ALLOWED_EXTENSIONS.include?(extension)
      end

      def image_extension(uri, content_type)
        from_path = File.extname(uri.path).downcase
        return from_path if allowed_extension?(from_path)

        CONTENT_TYPE_TO_EXTENSION[content_type.to_s.split(';').first]
      end

      def meets_minimum_dimensions?(data, source_url, stats)
        return true unless min_dimension.positive?

        image = MiniMagick::Image.read(data)
        if image.width >= min_dimension && image.height >= min_dimension
          true
        else
          logger.info(
            "Skipping #{source_url}: WebP image " \
            "#{image.width}x#{image.height} smaller than #{min_dimension}px"
          )
          stats[:skipped_small_images] += 1
          false
        end
      rescue MiniMagick::Error => e
        logger.warn "Failed to inspect dimensions for #{source_url}: #{e.message}"
        stats[:skipped_small_images] += 1
        false
      end
    end
  end
end
