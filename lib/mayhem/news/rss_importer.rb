# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'net/http'
require 'nokogiri'
require 'open-uri'
require 'openssl'
require 'reverse_markdown'
require 'rss'
require 'time'
require 'uri'
require 'yaml'
require_relative '../logging'
require_relative '../support/front_matter_document'
require_relative '../support/slug_generator'
require_relative '../support/http_client'
require_relative '../support/url_normalizer'
require_relative '../feed_discovery'

module Mayhem
  module News
    class RssImporter
      ARTICLE_BODY_SELECTORS = [
        '#news_content_body',
        '[id*="news_content_body"]',
        '.news_content_body',
        '[class*="news_content_body"]',
        '.news-body',
        '.article-body',
        '.article__body',
        '.news-article__body',
        'article .body'
      ].freeze

      MAX_ITEM_AGE_DAYS = 365
      MAX_FILENAME_BYTES = 255
      DEFAULT_NEWS_DIR = '_posts'
      DEFAULT_SOURCES_DIR = '_organizations'
      DEFAULT_MAX_WORKERS = begin
        Integer(ENV.fetch('RSS_WORKERS', '6'))
      rescue StandardError
        6
      end
      DEFAULT_OPEN_TIMEOUT = begin
        Integer(ENV.fetch('RSS_OPEN_TIMEOUT', '5'))
      rescue StandardError
        5
      end
      DEFAULT_READ_TIMEOUT = begin
        Integer(ENV.fetch('RSS_READ_TIMEOUT', '10'))
      rescue StandardError
        10
      end

      DEFAULT_CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        news_dir: DEFAULT_NEWS_DIR,
        sources_dir: DEFAULT_SOURCES_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        workers: DEFAULT_MAX_WORKERS,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        http_client: nil,
        max_item_age_days: nil,
        config_path: DEFAULT_CONFIG_PATH
      )
        @news_dir = news_dir
        @sources_dir = sources_dir
        @logger = logger
        @workers = [workers, 1].max
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @existing_posts = build_existing_post_index
        @existing_lock = Mutex.new
        FileUtils.mkdir_p(@news_dir)
        @http = http_client || Mayhem::Support::HttpClient.new(timeout: @read_timeout, logger: @logger)
        @max_item_age_days = determine_max_days(max_item_age_days, config_path)
      end

      def run
        queue = Queue.new
        Dir.glob(File.join(@sources_dir, '*.md')).each { |source_file| queue << source_file }

        threads = Array.new(@workers) do
          Thread.new do
            loop do
              source_file = queue.pop(true)
              process_source(source_file)
            rescue ThreadError
              break
            end
          end
        end
        threads.each(&:join)
      end

      private

      def process_source(source_file)
        frontmatter = Mayhem::Support::FrontMatterDocument.load(source_file, logger: @logger)
        return unless frontmatter

        rss_url = frontmatter['news_rss_url']
        source_title = frontmatter['title']
        return unless rss_url

        stats = Hash.new(0)
        page = @http.fetch(rss_url, accept: Mayhem::FeedDiscovery::ACCEPT_FEED, max_bytes: Mayhem::FeedDiscovery::FEED_MAX_BYTES)
        rss_content = page[:body]
        feed = RSS::Parser.parse(rss_content, false)
        feed.items.each do |item|
          process_item(item, source_title, stats, frontmatter)
        end

        @logger.info feed_summary_line(source_title, rss_url, stats)
      rescue OpenURI::HTTPError, SocketError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        @logger.error "Failed to fetch RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
      rescue OpenSSL::SSL::SSLError => e
        @logger.error "SSL error for source '#{source_title}' (#{rss_url}): #{e.message}"
      rescue RSS::NotWellFormedError => e
        @logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): #{e.message}"
      end

      def process_item(item, source_title, stats, source_frontmatter)
        link_url = item_link_url(item)
        normalized = Mayhem::Support::UrlNormalizer.normalize(link_url,
                                                              base: source_frontmatter && source_frontmatter['website'])
        if normalized.to_s.strip.empty?
          stats[:missing_link] += 1
          return
        end

        title_text = item_title_text(item).to_s.strip
        if title_text.empty?
          stats[:missing_title] += 1
          return
        end

        published_time = published_at(item)
        unless published_time
          stats[:missing_publish_date] += 1
          return
        end

        if stale_item?(published_time)
          stats[:stale] += 1
          return
        end

        original_html = item_content_html(item).to_s.strip
        original_html = fetch_article_body_html(normalized).to_s.strip if original_html.empty? && normalized
        if original_html.empty?
          stats[:empty_content] += 1
          return
        end

        if duplicate_post?(normalized)
          stats[:duplicates] += 1
          return
        end

        write_post(source_title, title_text, normalized, published_time, original_html)
        stats[:created] += 1
      end

      def duplicate_post?(link_url)
        normalized = link_url.to_s
        return false if normalized.empty?

        @existing_lock.synchronize { @existing_posts.key?(normalized) }
      end

      def register_post(link_url)
        normalized = link_url.to_s
        return if normalized.empty?

        @existing_lock.synchronize { @existing_posts[normalized] = true }
      end

      def write_post(source_title, title_text, link_url, published_time, original_html)
        content_md = ReverseMarkdown.convert(original_html)
        date_prefix = published_time.strftime('%Y-%m-%d')
        title_slug = Mayhem::Support::SlugGenerator.filename_slug(
          title: title_text,
          link: link_url,
          date_prefix: date_prefix,
          max_bytes: MAX_FILENAME_BYTES
        )
        filename = File.join(@news_dir, "#{date_prefix}-#{title_slug}.md")

        frontmatter = {
          'title' => title_text,
          'date' => published_time.iso8601,
          'source' => source_title,
          'source_url' => link_url.to_s,
          'original_content' => original_html
        }
        document = Mayhem::Support::FrontMatterDocument.new(
          path: filename,
          front_matter: frontmatter,
          body: "\n#{content_md}"
        )
        document.save
        register_post(link_url)
      end

      def published_at(item)
        candidates = []
        candidates << item.pubDate if item.respond_to?(:pubDate)
        candidates << item.dc_date if item.respond_to?(:dc_date)
        candidates << item.updated if item.respond_to?(:updated)
        candidates << item.date if item.respond_to?(:date)

        value = candidates.compact.first
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time)

        Time.parse(value.to_s) if value
      rescue StandardError
        nil
      end

      def stale_item?(published_time)
        cutoff = Time.now - (@max_item_age_days * 24 * 60 * 60)
        published_time < cutoff
      end

      def determine_max_days(override, config_path)
        return override if override

        value = read_config(config_path)
        return value if value.is_a?(Numeric)

        MAX_ITEM_AGE_DAYS
      end

      def read_config(config_path)
        return unless File.exist?(config_path)

        data = YAML.safe_load(File.read(config_path))
        data && data['rss_max_item_age_days']
      rescue StandardError => e
        @logger&.warn("Failed to read config #{config_path}: #{e.message}")
        nil
      end

      def fetch_article_body_html(url)
        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML, max_bytes: Mayhem::FeedDiscovery::HTML_MAX_BYTES)
        doc = Nokogiri::HTML(page[:body])
        ARTICLE_BODY_SELECTORS.each do |selector|
          node = doc.at_css(selector)
          next unless node

          snippet = node.inner_html.to_s.strip
          return snippet unless snippet.empty?
        end
        fallback = doc.at_css('main') || doc.at_css('#main') || doc.at_css('#content')
        fallback&.inner_html&.strip
      rescue OpenURI::HTTPError, OpenSSL::SSL::SSLError, SocketError,
             Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        @logger.warn "Failed to fetch article body (#{url}): #{e.message}"
        nil
      rescue StandardError => e
        @logger.error "Unexpected error scraping #{url}: #{e.message}"
        nil
      end

      def item_content_html(item)
        return item.content_encoded if item.respond_to?(:content_encoded) && item.content_encoded
        return item.description if item.respond_to?(:description) && item.description
        return item.summary if item.respond_to?(:summary) && item.summary

        content = item.content if item.respond_to?(:content)
        return content.content if content.respond_to?(:content) && content.content

        content if content.is_a?(String)
      rescue StandardError => e
        @logger.warn "Failed to read content for #{item.link || item.title}: #{e.message}"
        nil
      end

      def item_title_text(item)
        title = item.title if item.respond_to?(:title)
        return title.content if title.respond_to?(:content)

        title.to_s
      rescue StandardError
        item_link_url(item) || 'Untitled'
      end

      def item_link_url(item)
        if item.respond_to?(:link)
          link = item.link
          return link.href if link.respond_to?(:href)
          return link.to_s unless link.is_a?(RSS::Atom::Feed::Link)
        end
        if item.respond_to?(:links) && item.links.respond_to?(:each)
          alternate = item.links.find { |l| l.respond_to?(:rel) && l.rel == 'alternate' }
          return alternate.href if alternate.respond_to?(:href)

          first = item.links.first
          return first.href if first.respond_to?(:href)
        end
        item.respond_to?(:url) ? item.url.to_s : nil
      rescue StandardError => e
        @logger.warn "Failed to read link for #{item.respond_to?(:title) ? item.title : 'unknown item'}: #{e.message}"
        nil
      end

      def feed_summary_line(source_title, rss_url, stats)
        labels = {
          created: 'created',
          duplicates: 'duplicates',
          stale: 'stale',
          missing_link: 'missing_link',
          missing_title: 'missing_title',
          missing_publish_date: 'missing_date',
          empty_content: 'no_content'
        }
        parts = labels.map do |key, label|
          value = stats[key]
          "#{label}=#{value}" if value&.positive?
        end.compact
        status = parts.empty? ? 'no_changes' : parts.join(', ')
        "Processed '#{source_title}' (#{rss_url}): #{status}"
      end

      def build_existing_post_index
        Dir.glob(File.join(@news_dir, '*.md')).each_with_object({}) do |post_path, memo|
          doc = Mayhem::Support::FrontMatterDocument.load(post_path, logger: @logger)
          next unless doc

          fm = doc.front_matter
          next unless fm['original_content']

          url = fm['source_url'].to_s
          next if url.empty?

          memo[url] = true
        end
      end
    end
  end
end
