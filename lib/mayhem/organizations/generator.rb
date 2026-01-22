# frozen_string_literal: true

require 'fileutils'
require 'fmrepo'
require 'json'
require 'nokogiri'
require 'ruby/openai'
require 'seldon'
require 'uri'
require_relative '../models/organization'
require_relative '../models/topic'
require_relative '../feed/discovery'
require_relative '../sitemap/discovery'

module Mayhem
  module Organizations
    class Generator
      include Seldon::Loggable

      DEFAULT_TYPE = 'Community-Based Organization'
      MAX_PAGES = Integer(ENV.fetch('ORG_SCRAPER_MAX_PAGES', 5))
      PAGE_SNIPPET = Integer(ENV.fetch('ORG_SCRAPER_PAGE_SNIPPET', 3000))
      READ_TIMEOUT = Integer(ENV.fetch('ORG_SCRAPER_TIMEOUT', 10))
      OPENAI_MODEL = ENV.fetch('OPENAI_ORG_MODEL', 'gpt-4o-mini')

      def initialize(
        topic_repo: nil,
        topic_model: Mayhem::Models::Topic,
        client: nil,
        feed_finder: nil,
        sitemap_finder: nil,
        http_client: nil
      )
        @topic_repo = topic_repo
        @topic_model = topic_model
        @client = client
        @http = http_client || Seldon::Support::HttpClient.new(timeout: READ_TIMEOUT)
        @feed_finder = feed_finder || default_feed_finder
        @sitemap_finder = sitemap_finder || default_sitemap_finder
      end

      def run(raw_url)
        abort "Usage: #{File.basename($PROGRAM_NAME)} URL" unless raw_url

        website_url = canonical_url(raw_url)
        normalized = normalize_url(website_url)

        existing_websites = load_existing_websites
        existing_types = load_existing_types
        if existing_websites.include?(normalized)
          logger.info "Organization with website #{website_url} already exists; skipping."
          return
        end

        pages = gather_pages(website_url)
        abort "No content scraped from #{website_url}" if pages.empty?

        feed_result = discover_feed_urls(website_url)
        sitemap_urls = discover_sitemap_urls(website_url)
        topics = load_topics
        types = existing_types.empty? ? [DEFAULT_TYPE] : existing_types
        prompt = build_prompt(website_url, pages, topics, types)

        response = openai_client.chat(
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
        front_matter = build_front_matter(data, types: types)
        if feed_result
          front_matter['news_rss_url'] ||= feed_result.rss_url
          if (ical_url = Seldon::Support::ValueNormalizer.normalize_value(feed_result.ical_url))
            front_matter['events_ical_url'] ||= ical_url
          end
        end
        front_matter['website_xml_sitemap_urls'] = sitemap_urls.uniq if sitemap_urls&.any?
        front_matter['title'] = title
        front_matter['website_url'] = website_url

        body = body_from_data(data)
        record_id = write_organization_file(front_matter, body)
        logger.info "Created #{record_id}"
      end

      private

      def openai_client
        @openai_client ||= @client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      end

      def normalize_url(url)
        uri = URI(url)
        uri.fragment = nil
        uri.to_s.sub(%r{/$}, '').downcase
      rescue URI::InvalidURIError
        url.to_s.strip.downcase.sub(%r{/$}, '')
      end

      def canonical_url(url)
        uri = URI(url)
        uri = URI.parse("https://#{url}") if uri.host.nil?
        uri.scheme ||= 'https'
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        url
      end

      def load_existing_websites
        Mayhem::Models::Organization.all.each_with_object(Set.new) do |org, set|
          website_url = org.website_url
          next unless website_url

          set << normalize_url(website_url)
        end
      end

      def load_existing_types
        Mayhem::Models::Organization.all.each_with_object(Set.new) do |org, set|
          type = org.type
          set << type if type
        end
      end

      def fetch_page(url)
        page = @http.fetch(url, accept: FeedDiscovery::ACCEPT_HTML)
        Nokogiri::HTML(page[:body])
      rescue StandardError => e
        logger.warn "Skipping #{url}: #{e.class} #{e.message}"
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
        @topic_model.relation(repo: @topic_repo).filter_map(&:title).compact.sort
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
            - topic_titles (array of titles chosen from the allowed topics list, most relevant only)
            - parent_organization_title (string or null)
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

      def build_front_matter(data, types:)
        front_matter = {}
        %w[acronym news_rss_url events_ical_url parent_organization_title phone email address topic_titles
           type].each do |key|
          value = Seldon::Support::ValueNormalizer.normalize_value(data[key])
          front_matter[key] = value unless value.nil?
        end

        acronym = front_matter['acronym']
        front_matter['acronym'] = nil unless acronym&.match?(/\A[A-Z0-9&]{2,10}\z/)
        front_matter.compact!

        if (type_value = front_matter['type'])
          coerced = enforce_type(type_value, types)
          front_matter['type'] = coerced || DEFAULT_TYPE
        else
          front_matter['type'] = DEFAULT_TYPE
        end

        front_matter
      end

      def enforce_type(value, allowed)
        return nil if value.nil?

        allowed.find { |t| t.casecmp(value.to_s.strip).zero? }
      end

      def default_feed_finder
        Mayhem::FeedDiscovery::FeedFinder.new(@http)
      end

      def default_sitemap_finder
        Mayhem::SitemapDiscovery::Finder.new(http_client: @http)
      end

      def discover_feed_urls(website_url)
        return nil unless website_url

        @feed_finder&.find(website_url)
      rescue StandardError => e
        logger.warn "Feed discovery failed for #{website_url}: #{e.message}"
        nil
      end

      def discover_sitemap_urls(website_url)
        return nil unless website_url

        @sitemap_finder&.find(website_url) || []
      rescue StandardError => e
        logger.warn "Sitemap discovery failed for #{website_url}: #{e.message}"
        []
      end

      def absolutize(base, href)
        Seldon::Support::UrlUtils.absolutize(base, href)
      end

      def body_from_data(data)
        body = Seldon::Support::ValueNormalizer.normalize_value(data['summary']) || 'Description forthcoming.'
        word_limited = body.split(/\s+/)[0, 100].join(' ').strip
        word_limited.empty? ? 'Description forthcoming.' : word_limited
      end

      def write_organization_file(front_matter, body)
        new_org = Mayhem::Models::Organization.create!(
          front_matter,
          body: "\n#{body.strip}\n"
        )
        new_org.id || new_org.path
      end
    end
  end
end
