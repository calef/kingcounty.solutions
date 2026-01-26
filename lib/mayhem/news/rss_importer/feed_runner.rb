# frozen_string_literal: true

require 'faraday'
require 'rss'
require 'seldon'
require_relative '../../errors'
require_relative '../../feed/discovery'
require_relative 'feed_stats'

module Mayhem
  module News
    class RssImporter
      include Seldon::Loggable

      class FeedRunner
        include Seldon::Loggable

        def initialize(http_client:, feed_sanitizer:, item_processor:)
          @http = http_client
          @feed_sanitizer = feed_sanitizer
          @item_processor = item_processor
        end

        def process(source)
          rss_url = source.news_rss_url
          source_title = source.title
          return unless rss_url

          stats = FeedStats.new
          page = @http.fetch(rss_url, accept: Mayhem::FeedDiscovery::ACCEPT_FEED)
          unless feed_like?(page[:body], page[:content_type])
            log_non_feed_response(source_title, rss_url, page)
            return
          end
          rss_content = @feed_sanitizer.sanitize(page[:body], source_title, rss_url)
          feed = RSS::Parser.parse(rss_content, false)
          unless feed
            logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): parser returned nil"
            return
          end
          feed.items.each do |item|
            @item_processor.process(item, source_title, source, stats)
          end

          logger.info stats.summary_line(source_title, rss_url)
          stats
        rescue Seldon::Support::HttpClient::HttpError,
               Seldon::Support::HttpClient::NotFoundError,
               Seldon::Support::HttpClient::TooManyRequestsError,
               Seldon::Support::HttpClient::ServiceUnavailableError,
               *Mayhem::NetworkError::EXCEPTIONS => e
          logger.error "Failed to fetch RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
          nil
        rescue RSS::NotWellFormedError => e
          logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
          nil
        end

        private

        def feed_like?(data, content_type)
          snippet = normalize_string(data)
          preview = snippet.downcase
          ctype = (content_type || '').downcase

          return true if ctype.match?(%r{rss|atom|application/xml|text/xml|xml}) &&
                         preview.match?(/<(rss|feed|rdf)/)

          preview.match?(/<(rss|feed|rdf)/)
        end

        def normalize_string(data)
          return '' if data.nil?

          str = Seldon::Support::EncodingUtils.ensure_utf8(data)
          str.bytesize > 4_000 ? str[0, 4_000] : str
        end

        def log_non_feed_response(source_title, rss_url, page)
          snippet = normalize_string(page[:body]).strip
          details = []
          details << "content-type: #{page[:content_type]}" if page[:content_type]
          details << "final_url: #{page[:final_url]}" if page[:final_url] && page[:final_url] != rss_url
          details << 'blocked by SG captcha' if snippet.match?(/sgcaptcha|sg-captcha|robot challenge/i)
          details << "preview: #{snippet[0, 140]}" unless snippet.empty?
          suffix = details.empty? ? '' : " (#{details.join(', ')})"
          logger.error "Failed to fetch RSS feed for source '#{source_title}' (#{rss_url}): non-feed response#{suffix}"
        end
      end
    end
  end
end
