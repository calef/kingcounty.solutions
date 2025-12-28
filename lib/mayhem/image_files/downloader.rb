# frozen_string_literal: true

require 'uri'
require_relative 'validator'
require_relative '../feed/discovery'
require_relative '../logging'

module Mayhem
  module ImageFiles
    class Downloader
      include Mayhem::Loggable

      attr_reader :http_client, :validator

      def initialize(http_client:, validator:)
        @http_client = http_client
        @validator = validator
      end

      def download(url, stats)
        uri = URI.parse(url)
        return nil unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty?

        page = http_client.fetch(uri.to_s, accept: Mayhem::FeedDiscovery::ACCEPT_FEED, max_bytes: 2_097_152)
        ext = validator.image_extension(uri, page[:content_type])
        unless validator.allowed_extension?(ext)
          logger.info "Skipping #{url}: unsupported image type (#{ext || 'unknown'})"
          stats[:skipped_unsupported_images] += 1
          return nil
        end
        data = page[:body]
        { data:, ext: ext }
      rescue StandardError => e
        logger.warn "Failed to download #{url}: #{e.message}"
        stats[:download_failures] += 1
        nil
      end
    end
  end
end
