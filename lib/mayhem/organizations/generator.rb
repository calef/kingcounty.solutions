# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'ruby/openai'
require 'uri'
require_relative '../logging'
require_relative '../support/front_matter_document'
require_relative '../feed_discovery'
require_relative '../support/slug_generator'
require_relative '../support/http_client'
require_relative '../support/url_utils'

module Mayhem
  module Organizations
    class Generator
      ORG_DIR = '_organizations'
      TOPIC_DIR = '_topics'
      PLACE_DIR = '_places'
      DEFAULT_TYPE = 'Community-Based Organization'
      MAX_PAGES = Integer(ENV.fetch('ORG_SCRAPER_MAX_PAGES', 5))
      PAGE_SNIPPET = Integer(ENV.fetch('ORG_SCRAPER_PAGE_SNIPPET', 3000))
      READ_TIMEOUT = Integer(ENV.fetch('ORG_SCRAPER_TIMEOUT', 10))
      OPENAI_MODEL = ENV.fetch('OPENAI_ORG_MODEL', 'gpt-4o-mini')

      def initialize(
        org_dir: ORG_DIR,
        topic_dir: TOPIC_DIR,
        place_dir: PLACE_DIR,
        client: nil,
        feed_finder: nil,
        http_client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @org_dir = org_dir
        @topic_dir = topic_dir
        @place_dir = place_dir
        @logger = logger
        @client = client || OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Mayhem::Support::HttpClient.new(timeout: READ_TIMEOUT, logger: @logger)
        @feed_finder = feed_finder || default_feed_finder
      end

      def run(raw_url)
        abort "Usage: #{File.basename($PROGRAM_NAME)} URL" unless raw_url

        website_url = canonical_url(raw_url)
        normalized = normalize_url(website_url)

        existing_websites = load_existing_websites
        existing_types = load_existing_types
        if existing_websites.include?(normalized)
          @logger.info "Organization with website #{website_url} already exists; skipping."
          return
        end

        pages = gather_pages(website_url)
        abort "No content scraped from #{website_url}" if pages.empty?

        feed_result = discover_feed_urls(website_url)
        topics = load_topics
        places = load_place_titles
        types = existing_types.empty? ? [DEFAULT_TYPE] : existing_types
        prompt = build_prompt(website_url, pages, topics, types)

        response = @client.chat(
          parameters: {
            model: OPENAI_MODEL,
            temperature: 0.2,
            messages: [
              { role: 'system', content: 'You are a concise metadata extraction bot.' },
              { role: 'user', content: prompt }
            ]
          }
        )
        content = response.dig('choices', 0, 'message', 'content')
        data = parse_response(content) || {}

        title = data.fetch('title', URI(website_url).host)
        slug = ensure_unique_slug(slugify(title))
        front_matter = build_front_matter(data, topics: topics, places: places, types: types)
        if feed_result
          front_matter['news_rss_url'] ||= feed_result.rss_url
          front_matter['events_ical_url'] ||= feed_result.ical_url
        end
        front_matter['title'] = title
        front_matter['website'] = website_url

        body = body_from_data(data)
        path = write_organization_file(slug, front_matter, body)
        @logger.info "Created #{path}"
      end

      private

      def normalize_url(url)
        uri = URI(url)
        uri.fragment = nil
        uri.to_s.sub(%r{/$}, '').downcase
      rescue URI::InvalidURIError
        url.to_s.strip.downcase.sub(%r{/$}, '')
      end

      def canonical_url(url)
        uri = URI(url)
        uri.scheme ||= 'https'
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        url
      end

      def load_existing_websites
        Dir.glob(File.join(@org_dir, '*.md')).each_with_object(Set.new) do |path, set|
          doc = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless doc

          website = doc.front_matter['website']
          next unless website

          set << normalize_url(website)
        end
      end

      def load_existing_types
        Dir.glob(File.join(@org_dir, '*.md')).each_with_object(Set.new) do |path, set|
          doc = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless doc

          type = doc.front_matter['type']
          set << type if type
        end
      end

      def fetch_page(url)
        page = @http.fetch(url, accept: FeedDiscovery::ACCEPT_HTML, max_bytes: FeedDiscovery::HTML_MAX_BYTES)
        Nokogiri::HTML(page[:body])
      rescue StandardError => e
        @logger.warn "Skipping #{url}: #{e.class} #{e.message}"
        nil
      end

      def extract_text(doc)
        cleaned = doc.dup
        cleaned.search('script, style, nav, header, footer, noscript, iframe').remove
        cleaned.text.gsub(/\s+/, ' ').strip
      end

      def gather_pages(start_url)
        start_uri = URI(canonical_url(start_url))
        queue = [start_uri]
        seen = Set.new
        pages = []

        until queue.empty? || pages.size >= MAX_PAGES
          uri = queue.shift
          normalized = normalize_url(uri.to_s)
          next if seen.include?(normalized)

          seen << normalized
          doc = fetch_page(uri.to_s)
          next unless doc

          pages << { url: uri.to_s, text: extract_text(doc), doc: doc }

          doc.css('a[href]').map { |a| a['href'] }.compact.each do |href|
            begin
              link = URI.join(uri, href)
            rescue StandardError
              next
            end
            next unless link.host == start_uri.host

            normalized_link = normalize_url(link.to_s)
            next if seen.include?(normalized_link)
            next if queue.any? { |queued| normalize_url(queued.to_s) == normalized_link }

            queue << link
          end
        end

        pages
      end

      def load_topics
        Dir.glob(File.join(@topic_dir, '*.md')).filter_map do |path|
          doc = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless doc

          doc.front_matter['title']
        end.compact.sort
      end

      def load_place_titles
        Dir.glob(File.join(@place_dir, '*.md')).filter_map do |path|
          doc = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless doc

          doc.front_matter['title'] || File.basename(path, '.md').tr('-', ' ')
        end.compact.sort
      end

      def build_prompt(url, pages, topics, types)
        snippet = pages.map { |page| [page[:url], page[:text][0, PAGE_SNIPPET]].join("\n") }.join("\n\n")
        <<~PROMPT
          You are creating metadata for a local organization for a community resource directory.
          Only use the provided content. If unsure about a field, omit it or leave it empty.

          Allowed topic titles: #{topics.join('; ')}
          Allowed organization types: #{types.join('; ')}

          Return a JSON object with keys:
            - title (string, required)
            - type (string chosen from the allowed organization types)
            - acronym (string of capital letters like YMCA; omit if none)
            - jurisdictions (array of geographic place names mentioned in the content; omit if unclear)
            - topics (array of titles chosen from the allowed topics list, most relevant only)
            - parent_organization (string or null)
            - news_rss_url (string or null)
            - events_ical_url (string or null)
            - phone (string or null)
            - email (string or null)
            - address (string or null)
            - summary (markdown summary of services, maximum 100 words)

          Website to set: #{url}

          Scraped content:
          #{snippet}
        PROMPT
      end

      def parse_response(content)
        cleaned = content.to_s.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '')
        JSON.parse(cleaned)
      rescue JSON::ParserError
        nil
      end

      def slugify(title)
        slug = Mayhem::Support::SlugGenerator.sanitized_slug(title)
        slug = 'organization' if slug.to_s.strip.empty?
        slug
      end

      def ensure_unique_slug(base)
        slug = base
        idx = 1
        while File.exist?(File.join(@org_dir, "#{slug}.md"))
          slug = "#{base}-#{idx}"
          idx += 1
        end
        slug
      end

      def build_front_matter(data, topics:, places:, types:)
        front_matter = {}
        %w[acronym jurisdictions news_rss_url events_ical_url parent_organization phone email address topics
           type].each do |key|
          value = normalize_value(data[key])
          front_matter[key] = value unless value.nil?
        end

        acronym = front_matter['acronym']
        front_matter['acronym'] = nil unless acronym&.match?(/\A[A-Z0-9&]{2,10}\z/)
        front_matter.compact!

        if (juris = front_matter['jurisdictions'])
          allowed = places.to_set
          filtered = Array(juris).map(&:to_s).map(&:strip).reject(&:empty?).select { |j| allowed.include?(j) }.uniq
          front_matter['jurisdictions'] = filtered.empty? ? ['King County'] : filtered
        end

        if (type_value = front_matter['type'])
          coerced = enforce_type(type_value, types)
          front_matter['type'] = coerced || DEFAULT_TYPE
        else
          front_matter['type'] = DEFAULT_TYPE
        end

        front_matter
      end

      def normalize_value(value)
        return nil if value.nil?

        if value.is_a?(String)
          trimmed = value.strip
          return nil if trimmed.empty?

          trimmed
        elsif value.respond_to?(:empty?) && value.empty?
          nil
        else
          value
        end
      end

      def enforce_type(value, allowed)
        return nil if value.nil?

        allowed.find { |t| t.casecmp(value.to_s.strip).zero? }
      end

      def default_feed_finder
        Mayhem::FeedDiscovery::FeedFinder.new(@http, logger: @logger)
      end

      def discover_feed_urls(website_url)
        return nil unless website_url

        @feed_finder&.find(website_url)
      rescue StandardError => e
        @logger.warn "Feed discovery failed for #{website_url}: #{e.message}"
        nil
      end

      def absolutize(base, href)
        Mayhem::Support::UrlUtils.absolutize(base, href)
      end

      def body_from_data(data)
        body = normalize_value(data['summary']) || 'Description forthcoming.'
        word_limited = body.split(/\s+/)[0, 100].join(' ').strip
        word_limited.empty? ? 'Description forthcoming.' : word_limited
      end

      def write_organization_file(slug, front_matter, body)
        FileUtils.mkdir_p(@org_dir)
        path = File.join(@org_dir, "#{slug}.md")
        document = Mayhem::Support::FrontMatterDocument.new(
          path: path,
          front_matter: front_matter,
          body: "\n#{body.strip}\n"
        )
        document.save
        path
      end
    end
  end
end
