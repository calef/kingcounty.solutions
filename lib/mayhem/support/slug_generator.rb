# frozen_string_literal: true

require 'digest'

module Mayhem
  module Support
    module SlugGenerator
      module_function

      def sanitized_slug(text)
        text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
      end

      def filename_slug(title:, link:, date_prefix:, max_bytes: 255)
        base_slug = sanitized_slug(title)
        fallback_slug = Digest::SHA1.hexdigest(link.to_s)[0, 12]
        base_slug = fallback_slug if base_slug.empty?

        available = max_bytes - "#{date_prefix}-".bytesize - '.md'.bytesize
        available = 1 if available < 1

        return base_slug if base_slug.bytesize <= available

        digest = Digest::SHA1.hexdigest(link.to_s)[0, 8]
        truncated_length = available - digest.bytesize - 1
        truncated_length = 0 if truncated_length.negative?

        truncated = base_slug.byteslice(0, truncated_length)
        slug = [truncated, digest].reject(&:empty?).join('-')
        slug = fallback_slug if slug.empty?

        slug.bytesize > available ? slug.byteslice(0, available) : slug
      end
    end
  end
end
