# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'openssl'
require 'rss'
require_relative '../../feed/discovery'
require_relative 'feed_stats'

module Mayhem
  module News
    class RssImporter
      class FeedRunner
        def initialize(http_client:, logger:, feed_sanitizer:, item_processor:)
          @http = http_client
          @logger = logger
          @feed_sanitizer = feed_sanitizer
          @item_processor = item_processor
        end

        def process(source)
          rss_url = source.news_rss_url
          source_title = source.title
          return unless rss_url

          stats = FeedStats.new
          page = @http.fetch(rss_url, accept: Mayhem::FeedDiscovery::ACCEPT_FEED,
                                      max_bytes: Mayhem::FeedDiscovery::FEED_MAX_BYTES)
          rss_content = @feed_sanitizer.sanitize(page[:body], source_title, rss_url)
          feed = RSS::Parser.parse(rss_content, false)
          unless feed
            @logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): parser returned nil"
            return
          end
          feed.items.each do |item|
            @item_processor.process(item, source_title, source, stats)
          end

          @logger.info stats.summary_line(source_title, rss_url)
          stats
        rescue OpenURI::HTTPError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
          @logger.error "Failed to fetch RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
          nil
        rescue OpenSSL::SSL::SSLError => e
          @logger.error "SSL error for source '#{source_title}' (#{rss_url}): #{e.message}"
          nil
        rescue RSS::NotWellFormedError => e
          @logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
          nil
        end
      end
    end
  end
end
