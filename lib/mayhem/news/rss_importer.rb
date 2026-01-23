# frozen_string_literal: true

require 'seldon'
require_relative '../content/content_fetcher'
require_relative '../content/article_body_selectors'
require_relative '../models/news'
require_relative '../models/organization'
require_relative 'rss_importer/canonicalizer'
require_relative 'rss_importer/config'
require_relative 'rss_importer/duplicate_tracker'
require_relative 'rss_importer/feed_runner'
require_relative 'rss_importer/feed_sanitizer'
require_relative 'rss_importer/feed_stats'
require_relative 'rss_importer/guid_extractor'
require_relative 'rss_importer/item_parser'
require_relative 'rss_importer/item_processor'
require_relative 'rss_importer/post_writer'
require_relative 'rss_importer/source_enumerator'

module Mayhem
  module News
    class RssImporter
      include Seldon::Loggable

      ARTICLE_BODY_SELECTORS = Mayhem::Content::ArticleBodySelectors::SELECTORS

      DEFAULT_SOURCES_DIR = '_organizations'
      DEFAULT_MAX_WORKERS = begin
        Integer(ENV.fetch('RSS_WORKERS', '6'))
      rescue StandardError
        6
      end
      DEFAULT_OPEN_TIMEOUT = begin
        Integer(ENV.fetch('RSS_OPEN_TIMEOUT', '10'))
      rescue StandardError
        10
      end
      DEFAULT_READ_TIMEOUT = begin
        Integer(ENV.fetch('RSS_READ_TIMEOUT', '30'))
      rescue StandardError
        30
      end
      DEFAULT_FETCH_RETRIES = begin
        Integer(ENV.fetch('RSS_FETCH_RETRIES', '3'))
      rescue StandardError
        3
      end

      DEFAULT_CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        sources_dir: DEFAULT_SOURCES_DIR,
        news_model: Mayhem::Models::News,
        organization_model: Mayhem::Models::Organization,
        workers: DEFAULT_MAX_WORKERS,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        http_client: nil,
        fetch_retries: DEFAULT_FETCH_RETRIES,
        max_item_age_days: nil,
        config_path: DEFAULT_CONFIG_PATH
      )
        @sources_dir = sources_dir
        @news_model = news_model
        @organization_model = organization_model
        @workers = [workers, 1].max
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @fetch_retries = fetch_retries
        @http = http_client || Seldon::Support::HttpClient.new(
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          max_retries: @fetch_retries,
          cookie_jar: Seldon::Support::CookieJar.new
        )
        @content_fetcher = Mayhem::Content::ContentFetcher.new(
          http_client: @http,
          selectors: ARTICLE_BODY_SELECTORS
        )
        @config = Config.new(
          max_item_age_days: max_item_age_days,
          config_path: config_path
        )
        @duplicate_tracker = DuplicateTracker.new(news_model: @news_model)
        @canonicalizer = Canonicalizer.new(http_client: @http)
        @post_writer = PostWriter.new(news_model: @news_model)
        @item_parser = ItemParser.new
        @item_processor = ItemProcessor.new(
          item_parser: @item_parser,
          canonicalizer: @canonicalizer,
          content_fetcher: @content_fetcher,
          duplicate_tracker: @duplicate_tracker,
          post_writer: @post_writer,
          max_item_age_days: @config.max_item_age_days
        )
        @feed_sanitizer = FeedSanitizer.new
        @feed_runner = FeedRunner.new(
          http_client: @http,
          feed_sanitizer: @feed_sanitizer,
          item_processor: @item_processor
        )
        @source_enumerator = SourceEnumerator.new(
          organization_model: @organization_model,
          sources_dir: @sources_dir
        )
      end

      def run
        queue = Queue.new
        @source_enumerator.records.each { |source| queue << source }

        threads = Array.new(@workers) do
          Thread.new do
            loop do
              source_record = queue.pop(true)
              @feed_runner.process(source_record)
            rescue ThreadError
              break
            end
          end
        end
        threads.each(&:join)
      end
    end
  end
end
