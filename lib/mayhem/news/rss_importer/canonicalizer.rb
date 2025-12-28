# frozen_string_literal: true

require 'uri'
require_relative '../../support/url_normalizer'

module Mayhem
  module News
    class RssImporter
      class Canonicalizer
        CANONICAL_REDIRECT_HOSTS = %w[
          pubmed.ncbi.nlm.nih.gov
        ].freeze

        def initialize(http_client:, logger:)
          @http = http_client
          @logger = logger
        end

        def canonical_link(link_url, html_canonical: nil)
          return link_url if link_url.to_s.empty?

          if html_canonical
            normalized = Mayhem::Support::UrlNormalizer.normalize(html_canonical)
            return normalized if normalized
          end

          return link_url unless redirect_host?(link_url)

          resolved = @http.resolve_final_url(link_url)
          normalized = Mayhem::Support::UrlNormalizer.normalize(resolved)
          normalized || link_url
        rescue StandardError => e
          @logger.debug "Failed to canonicalize #{link_url}: #{e.message}"
          link_url
        end

        def redirect_host?(url)
          return false if url.to_s.empty?

          uri = URI.parse(url)
          host = uri.host&.downcase
          host && CANONICAL_REDIRECT_HOSTS.include?(host)
        rescue StandardError
          false
        end
      end
    end
  end
end
