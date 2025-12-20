# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'net/http'
require 'open-uri'
require 'openssl'
require 'nokogiri'
require 'rss'
require 'time'
require 'uri'
require 'yaml'
require_relative '../logging'
require_relative '../front_matter/document'
require_relative '../front_matter/slug_generator'
require_relative '../support/http_client'
require_relative '../support/url_normalizer'
require_relative '../content/content_fetcher'
require_relative '../content/article_body_selectors'
require_relative '../feed/discovery'
require_relative '../front_matter/publish_guard'
require_relative '../content/html_normalizer'

module Mayhem
  module News
    class RssImporter
      ARTICLE_BODY_SELECTORS = Mayhem::Content::ArticleBodySelectors::SELECTORS

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
      CANONICAL_REDIRECT_HOSTS = %w[
        pubmed.ncbi.nlm.nih.gov
      ].freeze

      def initialize(
        news_dir: DEFAULT_NEWS_DIR,
        sources_dir: DEFAULT_SOURCES_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        workers: DEFAULT_MAX_WORKERS,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        http_client: nil,
        fetch_retries: DEFAULT_FETCH_RETRIES,
        max_item_age_days: nil,
        config_path: DEFAULT_CONFIG_PATH
      )
        @news_dir = news_dir
        @sources_dir = sources_dir
        @logger = logger
        @workers = [workers, 1].max
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @fetch_retries = fetch_retries
        @existing_posts = build_existing_post_index
        @existing_lock = Mutex.new
        FileUtils.mkdir_p(@news_dir)
        @http = http_client || Mayhem::Support::HttpClient.new(
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          max_retries: @fetch_retries,
          logger: @logger
        )
        @max_item_age_days = determine_max_days(max_item_age_days, config_path)
        @content_fetcher = Mayhem::Content::ContentFetcher.new(
          http_client: @http,
          logger: @logger,
          selectors: ARTICLE_BODY_SELECTORS
        )
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
        frontmatter = Mayhem::FrontMatter::Document.load(source_file, logger: @logger)
        return unless frontmatter

        rss_url = frontmatter['news_rss_url']
        source_title = frontmatter['title']
        return unless rss_url

        stats = Hash.new(0)
        page = @http.fetch(rss_url, accept: Mayhem::FeedDiscovery::ACCEPT_FEED,
                                    max_bytes: Mayhem::FeedDiscovery::FEED_MAX_BYTES)
        rss_content = sanitize_feed_xml(page[:body], source_title, rss_url)
        feed = RSS::Parser.parse(rss_content, false)
        unless feed
          @logger.error "Failed to parse RSS feed for source '#{source_title}' (#{rss_url}): parser returned nil"
          return
        end
        feed.items.each do |item|
          process_item(item, source_title, stats, frontmatter)
        end

        @logger.info feed_summary_line(source_title, rss_url, stats)
      rescue OpenURI::HTTPError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
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
        normalized = canonical_link(normalized)
        if normalized.to_s.strip.empty?
          stats[:missing_link] += 1
          return
        end
        guid_value = item_guid(item)

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
        body_data = nil
        force_unpublished = false
        if normalized && (original_html.empty? || canonical_redirect_host?(normalized))
          body_data = fetch_article_body(normalized)
          force_unpublished = true if body_data && body_data[:not_found]
          fetched_html = body_data[:html].to_s.strip
          original_html = fetched_html if original_html.empty?
        end
        if body_data && body_data[:canonical_url]
          updated = canonical_link(normalized, html_canonical: body_data[:canonical_url])
          if updated && updated != normalized
            normalized = updated
            if duplicate_post?(normalized, guid_value)
              stats[:duplicates] += 1
              return
            end
          end
        end
        if original_html.empty?
          if force_unpublished
            stats[:not_found] += 1
          else
            stats[:empty_content] += 1
            return
          end
        end

        if duplicate_post?(normalized, guid_value)
          stats[:duplicates] += 1
          return
        end

        publish_flag = force_unpublished ? false : nil
        result = write_post(
          source_title,
          title_text,
          normalized,
          published_time,
          original_html,
          guid_value,
          published: publish_flag
        )
        case result
        when :created
          stats[:created] += 1
        when :skipped_unpublished
          stats[:skipped_unpublished] += 1
        when :skipped_unchanged
          stats[:unchanged] += 1
        when :skipped_locked
          stats[:locked] += 1
        end
      end

      def duplicate_post?(link_url, guid = nil)
        keys = []
        keys << post_key_for_link(link_url)
        keys << post_key_for_guid(guid)
        keys.compact!
        return false if keys.empty?

        @existing_lock.synchronize { keys.any? { |key| @existing_posts.key?(key) } }
      end

      def register_post(link_url, guid = nil)
        keys = []
        keys << post_key_for_link(link_url)
        keys << post_key_for_guid(guid)
        keys.compact!
        return if keys.empty?

        @existing_lock.synchronize do
          keys.each { |key| @existing_posts[key] = true }
        end
      end

      def post_key_for_link(link_url)
        normalized = link_url.to_s.strip
        return nil if normalized.empty?

        "link:#{normalized}"
      end

      def post_key_for_guid(guid_value)
        guid_text = extract_guid_text(guid_value)
        return nil unless guid_text

        "guid:#{guid_text}"
      end

      def extract_guid_text(raw_guid)
        return nil unless raw_guid

        candidate =
          if raw_guid.respond_to?(:content) && raw_guid.content
            raw_guid.content
          elsif raw_guid.respond_to?(:href) && raw_guid.href
            raw_guid.href
          elsif raw_guid.respond_to?(:value) && raw_guid.value
            raw_guid.value
          else
            raw_guid.to_s
          end
        text = candidate.to_s.strip
        text.empty? ? nil : text
      end

      def write_post(source_title, title_text, link_url, published_time, original_html, rss_guid = nil, published: nil)
        normalized_html = Mayhem::Content::HtmlNormalizer.normalize(original_html, base_url: link_url)
        checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_html)
        date_prefix = published_time.strftime('%Y-%m-%d')
        title_slug = Mayhem::FrontMatter::SlugGenerator.filename_slug(
          title: title_text,
          link: link_url,
          date_prefix: date_prefix,
          max_bytes: MAX_FILENAME_BYTES
        )
        filename = File.join(@news_dir, "#{date_prefix}-#{title_slug}.md")

        if locked_post?(filename)
          @logger.info "Skipping update for locked post #{filename}"
          register_post(link_url, rss_guid)
          return :skipped_locked
        end

        if Mayhem::FrontMatter::PublishGuard.unpublished?(filename, logger: @logger)
          @logger.info "Skipping update for unpublished post #{filename}"
          register_post(link_url, rss_guid)
          return :skipped_unpublished
        end

        if unchanged_post?(filename, normalized_html, checksum, link_url)
          @logger.debug "Skipping unchanged post #{filename}"
          register_post(link_url, rss_guid)
          return :skipped_unchanged
        end

        frontmatter = {
          'title' => title_text,
          'date' => published_time.iso8601,
          'source' => source_title,
          'source_url' => link_url.to_s,
          'rss_guid' => rss_guid,
          'feed_content' => normalized_html,
          'feed_content_checksum' => checksum
        }
        frontmatter['published'] = false if published == false
        document = Mayhem::FrontMatter::Document.new(
          path: filename,
          front_matter: frontmatter,
          body: ''
        )
        document.save
        register_post(link_url, rss_guid)
        :created
      end

      def locked_post?(filename)
        Mayhem::FrontMatter::Document.locked?(filename, logger: @logger)
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

        data = YAML.safe_load_file(config_path)
        data && data['rss_max_item_age_days']
      rescue StandardError => e
        @logger&.warn("Failed to read config #{config_path}: #{e.message}")
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

      def item_guid(item)
        return extract_guid_text(item.guid) if item.respond_to?(:guid) && item.guid
        return extract_guid_text(item.id) if item.respond_to?(:id) && item.id

        nil
      rescue StandardError => e
        @logger.warn "Failed to read guid for #{item.respond_to?(:title) ? item.title : 'unknown item'}: #{e.message}"
        nil
      end

      def feed_summary_line(source_title, rss_url, stats)
        labels = {
          created: 'created',
          duplicates: 'duplicates',
          not_found: 'not_found',
          stale: 'stale',
          missing_link: 'missing_link',
          missing_title: 'missing_title',
          missing_publish_date: 'missing_date',
          empty_content: 'no_content',
          skipped_unpublished: 'unpublished_locked',
          unchanged: 'unchanged',
          locked: 'locked'
        }
        parts = labels.map do |key, label|
          value = stats[key]
          "#{label}=#{value}" if value&.positive?
        end.compact
        status = parts.empty? ? 'no_changes' : parts.join(', ')
        "Processed '#{source_title}' (#{rss_url}): #{status}"
      end

      def sanitize_feed_xml(xml, source_title, rss_url)
        return xml unless xml

        doc = Nokogiri::XML(xml) { |config| config.nonet.recover }
        return xml unless doc

        declared_prefixes = doc.collect_namespaces.keys.map do |name|
          name.split(':', 2).last
        end.compact.to_set
        removed_nodes = false

        doc.traverse do |node|
          next unless node.element?

          if undeclared_prefix?(node, declared_prefixes)
            node.remove
            removed_nodes = true
            next
          end

          node.attribute_nodes.each do |attr|
            next unless undeclared_prefix?(attr, declared_prefixes)

            attr.remove
            removed_nodes = true
          end
        end

        @logger.info "Sanitized namespaced XML for '#{source_title}' (#{rss_url}) due to undeclared prefixes" if removed_nodes
        remove_duplicate_xml_declaration(doc)
        doc.to_xml
      rescue StandardError => e
        @logger.warn "Failed to sanitize feed XML for '#{source_title}' (#{rss_url}): #{e.message}"
        xml
      end

      def undeclared_prefix?(node_or_attr, declared_prefixes)
        ns = node_or_attr.namespace
        return false if ns

        name = node_or_attr.name
        return false unless name&.include?(':')

        prefix = name.split(':', 2).first
        return false if declared_prefixes.include?(prefix)

        true
      end

      def remove_duplicate_xml_declaration(doc)
        doc.children.each do |child|
          next unless child.processing_instruction?
          next unless child.name.to_s.casecmp('xml').zero?

          child.remove
        end
      end

      def build_existing_post_index
        Dir.glob(File.join(@news_dir, '*.md')).each_with_object({}) do |post_path, memo|
          doc = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)
          next unless doc

          fm = doc.front_matter
          next unless fm['feed_content']

          url = Mayhem::Support::UrlNormalizer.normalize(fm['source_url'])
          key = post_key_for_link(url)
          memo[key] = true if key

          guid_key = post_key_for_guid(fm['rss_guid'])
          memo[guid_key] = true if guid_key
        end
      end

      def unchanged_post?(filename, normalized_html, checksum, link_url)
        return false unless File.exist?(filename)

        document = Mayhem::FrontMatter::Document.load(filename, logger: @logger)
        return false unless document

        front_matter = document.front_matter
        existing_checksum = front_matter['feed_content_checksum'].to_s
        return true if !existing_checksum.empty? && existing_checksum == checksum

        existing_content = front_matter['feed_content']
        return false unless existing_content

        base_url = front_matter['source_url'].to_s
        base_url = link_url if base_url.empty?
        existing_normalized = Mayhem::Content::HtmlNormalizer.normalize(existing_content, base_url: base_url)
        existing_normalized == normalized_html
      rescue StandardError => e
        @logger.debug "Failed to compare existing post #{filename}: #{e.message}"
        false
      end

      def canonical_link(link_url, html_canonical: nil)
        return link_url if link_url.to_s.empty?

        if html_canonical
          normalized = Mayhem::Support::UrlNormalizer.normalize(html_canonical)
          return normalized if normalized
        end

        return link_url unless canonical_redirect_host?(link_url)

        resolved = @http.resolve_final_url(link_url)
        normalized = Mayhem::Support::UrlNormalizer.normalize(resolved)
        normalized || link_url
      rescue StandardError => e
        @logger.debug "Failed to canonicalize #{link_url}: #{e.message}"
        link_url
      end

      def canonical_redirect_host?(url)
        return false if url.to_s.empty?

        uri = URI.parse(url)
        host = uri.host&.downcase
        host && CANONICAL_REDIRECT_HOSTS.include?(host)
      rescue StandardError
        false
      end

      def fetch_article_body(url)
        return { html: '', canonical_url: nil } unless url

        @content_fetcher.fetch(url)
      rescue Mayhem::Support::HttpClient::NotFoundError => e
        @logger.warn "Article URL returned 404 (#{url}): #{e.message}"
        { html: '', canonical_url: url, not_found: true }
      rescue OpenURI::HTTPError, OpenSSL::SSL::SSLError, SocketError,
             Net::OpenTimeout, Net::ReadTimeout => e
        @logger.warn "Failed to fetch article body (#{url}): #{e.message}"
        { html: '', canonical_url: nil }
      rescue StandardError => e
        @logger.error "Unexpected error scraping #{url}: #{e.message}"
        { html: '', canonical_url: nil }
      end
    end
  end
end
