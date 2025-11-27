# frozen_string_literal: true

require 'uri'

module Mayhem
  module Support
    module UrlNormalizer
      extend self

      # Normalize a link and ensure it is a valid http/https URL string or return nil.
      # link can be a String or object with to_s; base is optional website base URL.
      def normalize(link, base: nil)
        link_str = link.to_s.strip
        return nil if link_str.empty?

        base = base.to_s if base

        # protocol-relative
        link_str = "https:#{link_str}" if link_str.start_with?('//')

        uri = parse_uri_with_https_fallback(link_str)
        return uri.to_s if uri&.scheme && uri.host && uri.scheme.match?(/\Ahttps?\z/)

        if base && !base.empty?
          begin
            joined = URI.join(base, link_str).to_s
            parsed = URI.parse(joined)
            return parsed.to_s if parsed.scheme && parsed.host && parsed.scheme.match?(/\Ahttps?\z/)
          rescue StandardError
            return nil
          end
        end

        nil
      end

      private

      def parse_uri_with_https_fallback(str)
        URI.parse(str)
      rescue URI::InvalidURIError
        begin
          URI.parse("https://#{str}")
        rescue URI::InvalidURIError
          nil
        end
      end
    end
  end
end
