# frozen_string_literal: true

require 'uri'
module Mayhem
  module Support
    module UrlUtils
      # This file intentionally mirrors common URL helper behavior used across the project.
      # Methods are available as module-level methods and as instance methods when mixed in.

      NON_FEED_URL_PATTERNS = [
        /\.(pdf|docx?|xlsx?|pptx?|zip)(\?|$)/i,
        %r{DocumentCenter/(View|Download)/}i
      ].freeze

      module_function

      def absolutize(base_url, href)
        return nil if href.nil?

        cleaned = href.strip
        return nil if cleaned.empty? || cleaned.start_with?('#')

        downcased = cleaned.downcase
        return nil if downcased.start_with?('javascript:', 'data:', 'mailto:')

        base = URI.parse(base_url)
        URI.join(base, cleaned).to_s
      rescue URI::Error
        nil
      end

      def parse_host(url)
        URI.parse(url).host
      rescue URI::Error
        nil
      end

      def enforce_https(base_url, candidate_url)
        return candidate_url unless candidate_url&.match?(%r{\Ahttps?://})
        return candidate_url if candidate_url.start_with?('https://')

        return candidate_url unless base_url&.start_with?('https://')

        candidate_host = parse_host(candidate_url)
        base_host = parse_host(base_url)
        return candidate_url unless candidate_host && base_host && candidate_host == base_host

        candidate_url.sub(/\Ahttp:/, 'https:')
      end

      def non_feed_url?(url)
        return false unless url

        NON_FEED_URL_PATTERNS.any? { |pattern| url.match?(pattern) }
      end
    end
  end
end
