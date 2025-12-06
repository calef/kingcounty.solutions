# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'openssl'
require 'uri'
require 'mayhem/logging'
require_relative 'support/http_client'
require_relative 'support/url_utils'

module Mayhem
  module FeedDiscovery
    LOGGER = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    UrlHelpers = Mayhem::Support::UrlUtils
    HttpClient = Mayhem::Support::HttpClient
    UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/537.36 ' \
         '(KHTML, like Gecko) Chrome/125.0 Safari/537.36'
    HTML_MAX_BYTES = 1_048_576
    FEED_MAX_BYTES = 2_097_152
    REQUEST_DELAY = 0.15
    ACCEPT_HTML = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    ACCEPT_FEED = 'application/rss+xml, application/atom+xml, application/xml;q=0.9, ' \
                  'text/xml;q=0.8, text/calendar;q=0.7, */*;q=0.1'
    MAX_REDIRECTS = 5
    LINK_ATTR_PATTERNS = {
      type: [[/rss|atom|xml|calendar/, 5]],
      rel: [[/alternate|feed|rss|atom|calendar/, 4]],
      title: [[/rss|feed|calendar/, 1]]
    }.freeze
    LINK_HREF_PATTERNS = [
      [/rss|feed|atom|\.xml|\.ics/, 2],
      [/news/, 1],
      [%r{/feed/}, 1],
      [%r{comments/feed}, -1]
    ].freeze
    ANCHOR_HREF_PATTERNS = [
      [/rss|feed|atom|\.ics/, 2],
      [/(\.(xml|rss|atom|ics))\z/, 2],
      [/news/, 1],
      [%r{/feed/}, 1],
      [%r{comments/feed}, -1]
    ].freeze
    ANCHOR_ATTR_PATTERNS = [[/rss|feed|calendar/, 1]].freeze
    SECONDARY_KEYWORDS = %w[
      news blog stories updates press release releases media article articles feed feeds
      posts announcements resources impact calendar
    ].freeze
    NON_FEED_URL_PATTERNS = [
      /\.(pdf|docx?|xlsx?|pptx?|zip)(\?|$)/i,
      %r{DocumentCenter/(View|Download)/}i
    ].freeze

    FeedResult = Struct.new(:rss_url, :ical_url) do
      def add(kind, url)
        return if url.nil? || url.empty?

        case kind
        when :rss
          self.rss_url ||= url
        when :ical
          self.ical_url ||= url
        end
      end

      def merge!(other)
        return self unless other

        add(:rss, other.rss_url)
        add(:ical, other.ical_url)
        self
      end

      def missing_types
        [].tap do |list|
          list << :rss unless rss_url
          list << :ical unless ical_url
        end
      end

      def found_types
        [].tap do |list|
          list << :rss if rss_url
          list << :ical if ical_url
        end
      end

      def any?
        rss_url || ical_url
      end

      def complete?
        rss_url && ical_url
      end
    end

    class CandidateCollector
      include UrlHelpers

      def initialize(html, final_url)
        @html = html
        @doc = Nokogiri::HTML(html)
        @final_url = final_url
      end

      def collect
        base_url = base_url_for
        candidates = gather_node_candidates(base_url)
        append_wordpress_guess(candidates, base_url)
        append_fallback_links(candidates, base_url)
        deduplicate_candidates(candidates)
      end

      private

      def base_url_for
        base_href = @doc.at('base')&.[]('href')
        base_href ? (absolutize(@final_url, base_href) || @final_url) : @final_url
      end

      def gather_node_candidates(base_url)
        @doc.css('link, a').each_with_object([]) do |node, memo|
          abs_url = absolutize(base_url, node['href'])
          abs_url = enforce_https(base_url, abs_url)
          next unless abs_url
          next unless abs_url.start_with?('https://')
          next if non_feed_url?(abs_url)

          score = node_candidate_score(node, abs_url.downcase)
          memo << [score, abs_url] if score&.positive?
        end
      end

      def node_candidate_score(node, href_lower)
        score = if node.name == 'link'
                  link_node_score(node, href_lower)
                else
                  anchor_node_score(node, href_lower)
                end
        score&.positive? ? score : nil
      end

      def link_node_score(node, href_lower)
        attr_values = {
          type: node['type'].to_s.downcase,
          rel: node['rel'].to_s.downcase,
          title: node['title'].to_s.downcase
        }
        score = attribute_scores(attr_values, LINK_ATTR_PATTERNS)
        score += pattern_score(href_lower, LINK_HREF_PATTERNS)
        score.positive? ? score + 10 : score
      end

      def anchor_node_score(node, href_lower)
        class_lower = node['class'].to_s.downcase
        id_lower = node['id'].to_s.downcase
        score = pattern_score(href_lower, ANCHOR_HREF_PATTERNS)
        attr_score = ANCHOR_ATTR_PATTERNS.sum do |pattern, weight|
          attribute_pattern_score(class_lower, pattern, weight) +
            attribute_pattern_score(id_lower, pattern, weight)
        end
        score + attr_score
      end

      def attribute_scores(values, pattern_map)
        pattern_map.sum do |attr, patterns|
          value = values[attr]
          patterns.sum { |pattern, weight| attribute_pattern_score(value, pattern, weight) }
        end
      end

      def attribute_pattern_score(value, pattern, weight)
        value.match?(pattern) ? weight : 0
      end

      def pattern_score(value, patterns)
        patterns.sum { |pattern, weight| value.match?(pattern) ? weight : 0 }
      end

      def append_wordpress_guess(candidates, base_url)
        return unless @html.downcase.include?('wordpress')

        guessed = absolutize(base_url, '/feed/')
        candidates << [25, guessed] if guessed
      end

      def append_fallback_links(candidates, base_url)
        return unless candidates.empty?

        @html.scan(/href=["']([^"']+rss[^"']*)["']/i).each do |match|
          guessed = absolutize(base_url, match.first)
          guessed = enforce_https(base_url, guessed)
          next unless guessed
          next unless guessed.start_with?('https://')
          next if non_feed_url?(guessed)

          candidates << [3, guessed]
        end
      end

      def deduplicate_candidates(candidates)
        dedup = {}
        candidates.each do |score, url|
          next unless url&.match?(%r{\Ahttps?://})

          dedup[url] = [dedup[url] || score, score].compact.max
        end

        dedup.sort_by { |url, score| [-score, url] }.map(&:first)
      end
    end

    class SecondaryPageCollector
      include UrlHelpers

      def initialize(html, final_url)
        @html = html
        @doc = Nokogiri::HTML(html)
        @final_url = final_url
      end

      def collect
        base_url = base_url_for
        base_host = parse_host(base_url)

        scored = @doc.css('a[href]').each_with_object([]) do |node, memo|
          abs_url = absolutize(base_url, node['href'])
          abs_url = enforce_https(base_url, abs_url)
          next unless abs_url&.match?(%r{\Ahttps?://})
          next if non_feed_url?(abs_url)

          score = score_secondary_link(abs_url, node, base_host)
          memo << [score, abs_url] if score.positive?
        end

        deduplicate_candidates(scored)
      end

      private

      def base_url_for
        base_href = @doc.at('base')&.[]('href')
        base_href ? (absolutize(@final_url, base_href) || @final_url) : @final_url
      end

      def score_secondary_link(abs_url, node, base_host)
        href_lower = abs_url.downcase
        text_lower = node.text.to_s.downcase
        class_lower = node['class'].to_s.downcase
        id_lower = node['id'].to_s.downcase

        score = SECONDARY_KEYWORDS.sum do |keyword|
          keyword_score(keyword, href_lower, text_lower, class_lower, id_lower)
        end
        score + (same_host?(abs_url, base_host) ? 1 : 0)
      end

      def keyword_score(keyword, href_lower, text_lower, class_lower, id_lower)
        value = 0
        value += 3 if href_lower.include?(keyword)
        value += 2 if text_lower.include?(keyword)
        value += 1 if class_lower.include?(keyword) || id_lower.include?(keyword)
        value
      end

      def same_host?(abs_url, base_host)
        base_host && parse_host(abs_url) == base_host
      rescue URI::Error
        false
      end

      def deduplicate_candidates(candidates)
        dedup = {}
        candidates.each do |score, url|
          next unless url&.match?(%r{\Ahttps?://})

          dedup[url] = [dedup[url] || score, score].compact.max
        end

        dedup.sort_by { |url, score| [-score, url] }.map(&:first)
      end
    end

    class FeedFinder
      include UrlHelpers

      def initialize(http_client, logger: LOGGER)
        @http = http_client
        @logger = logger
      end

      def find(website)
        page = @http.fetch(website, accept: ACCEPT_HTML, max_bytes: HTML_MAX_BYTES)
        result = feed_result_from_response(page[:body], page[:content_type], page[:final_url])
        html = decode_html(page[:body])
        html_result = feed_from_html(html, page[:final_url])
        result ||= FeedResult.new
        result.merge!(html_result)
        result.any? ? result : nil
      rescue StandardError => e
        @logger.warn "fetch error for #{website}: #{e.message}"
        nil
      end

      private

      def feed_result_from_response(body, content_type, final_url)
        kind = feed_type(body, content_type)
        return nil unless kind

        case kind
        when :rss
          FeedResult.new(final_url, nil)
        when :ical
          FeedResult.new(nil, final_url)
        end
      end

      def feed_from_html(html, final_url)
        result = find_feed_in_html(html, final_url)
        missing = result.missing_types
        if missing.any?
          secondary = find_feed_in_secondary_pages(html, final_url, missing)
          result.merge!(secondary)
        end
        result
      end

      def find_feed_in_html(html, final_url, needed_types = nil)
        needed = Array(needed_types) if needed_types
        result = FeedResult.new
        candidates = collect_candidates(html, final_url)
        candidates.first(8).each do |candidate|
          break if needed.nil? && result.complete?

          kind, url = verify_feed(candidate)
          next unless kind
          next if needed && !needed.include?(kind)

          result.add(kind, url)
          break if needed && (needed - result.found_types).empty?
        end
        result
      end

      def find_feed_in_secondary_pages(html, final_url, needed_types)
        return FeedResult.new if needed_types.empty?

        result = FeedResult.new
        candidates = secondary_page_candidates(html, final_url)
        candidates.first(3).each do |secondary_url|
          begin
            page = fetch_secondary_page(secondary_url)
          rescue StandardError => e
            @logger.warn "Secondary page error for #{secondary_url}: #{e.message}"
            next
          end
          page_html = decode_html(page[:body])
          missing = needed_types - result.found_types
          page_result = find_feed_in_html(page_html, page[:final_url], missing)
          result.merge!(page_result)
          break if (needed_types - result.found_types).empty?
        end
        result
      end

      def collect_candidates(html, final_url)
        CandidateCollector.new(html, final_url).collect
      end

      def secondary_page_candidates(html, final_url)
        SecondaryPageCollector.new(html, final_url).collect
      end

      def fetch_secondary_page(secondary_url)
        @http.fetch(secondary_url, accept: ACCEPT_HTML, max_bytes: HTML_MAX_BYTES)
      end

      def verify_feed(url)
        response = @http.fetch(url, accept: ACCEPT_FEED, max_bytes: FEED_MAX_BYTES)
        kind = feed_type(response[:body], response[:content_type])
        return [kind, response[:final_url]] if kind

        snippet = normalize_string(response[:body]).strip
        return [:rss, response[:final_url]] if snippet.start_with?('{') && snippet.include?('rss')

        nil
      rescue StandardError => e
        @logger.warn "Verify error for #{url}: #{e.message}"
        nil
      end

      def feed_type(body, content_type)
        return :rss if feed_like?(body, content_type)
        return :ical if calendar_like?(body, content_type)

        nil
      end

      def feed_like?(data, content_type)
        snippet = normalize_string(data)
        preview = snippet.downcase
        ctype = (content_type || '').downcase

        return true if ctype.match?(%r{rss|atom|application/xml|text/xml|xml}) &&
                       preview.match?(/<(rss|feed|rdf)/)

        preview.match?(/<(rss|feed|rdf)/)
      end

      def calendar_like?(data, content_type)
        snippet = normalize_string(data)
        preview = snippet.downcase
        ctype = (content_type || '').downcase

        return true if ctype.include?('calendar')

        preview.include?('begin:vcalendar')
      end

      def decode_html(data)
        snippet = data.dup
        snippet.force_encoding('BINARY')
        snippet.encode('UTF-8', invalid: :replace, undef: :replace)
      rescue EncodingError
        snippet.force_encoding('UTF-8')
      end

      def normalize_string(data)
        return '' if data.nil?

        str = data.dup
        str.force_encoding('BINARY')
        str = str[0, 4_000] if str.bytesize > 4_000
        str.encode('UTF-8', invalid: :replace, undef: :replace)
      rescue EncodingError
        str.force_encoding('UTF-8')
      end
    end
  end
end
