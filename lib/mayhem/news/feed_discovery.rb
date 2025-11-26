# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'openssl'
require 'uri'
require_relative '../logging'

module Mayhem
  module News
    module FeedDiscovery
      LOGGER = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/537.36 ' \
           '(KHTML, like Gecko) Chrome/125.0 Safari/537.36'
      HTML_MAX_BYTES = 1_048_576
      FEED_MAX_BYTES = 524_288
      REQUEST_DELAY = 0.15
      ACCEPT_HTML = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      ACCEPT_FEED = 'application/rss+xml, application/atom+xml, application/xml;q=0.9, ' \
                    'text/xml;q=0.8, */*;q=0.1'
      MAX_REDIRECTS = 5
      LINK_ATTR_PATTERNS = {
        type: [[/rss|atom|xml/, 5]],
        rel: [[/alternate|feed|rss|atom/, 4]],
        title: [[/rss|feed/, 1]]
      }.freeze
      LINK_HREF_PATTERNS = [
        [/rss|feed|atom|\.xml/, 2],
        [/news/, 1],
        [%r{/feed/}, 1],
        [%r{comments/feed}, -1]
      ].freeze
      ANCHOR_HREF_PATTERNS = [
        [/rss|feed|atom/, 2],
        [/\.(xml|rss|atom)\z/, 2],
        [/news/, 1],
        [%r{/feed/}, 1],
        [%r{comments/feed}, -1]
      ].freeze
      ANCHOR_ATTR_PATTERNS = [[/rss|feed/, 1]].freeze
      SECONDARY_KEYWORDS = %w[
        news blog stories updates press release releases media article articles feed feeds
        posts announcements resources impact
      ].freeze

      module UrlHelpers
        def absolutize(base_url, href)
          return nil if href.nil?

          cleaned = href.strip
          return nil if cleaned.empty? || cleaned.start_with?('#')

          downcased = cleaned.downcase
          return nil if downcased.start_with?('javascript:', 'data:', 'mailto:')

          base = URI.parse(base_url)
          URI.join(base, cleaned).to_s
        rescue URI::Error
          nil
        end

        def parse_host(url)
          URI.parse(url).host
        rescue URI::Error
          nil
        end
      end

      class HttpClient
        include UrlHelpers

        def initialize(
          user_agent: UA,
          delay: REQUEST_DELAY,
          max_redirects: MAX_REDIRECTS,
          timeout: 20,
          allow_insecure_fallback: true,
          logger: LOGGER
        )
          @user_agent = user_agent
          @delay = delay
          @max_redirects = max_redirects
          @read_timeout = timeout
          @open_timeout = timeout
          @allow_insecure_fallback = allow_insecure_fallback
          @logger = logger
        end

        def fetch(url, accept:, max_bytes:)
          response = perform_request(url, accept, max_bytes, @max_redirects)
          sleep @delay
          response
        end

        private

        def perform_request(url, accept, max_bytes, remaining_redirects)
          uri = URI.parse(url)
          response, body = execute_request(uri, accept, max_bytes)
          if response.is_a?(Net::HTTPRedirection)
            return follow_redirect(response, uri, accept, max_bytes, remaining_redirects)
          end

          {
            body: body,
            content_type: response['content-type'],
            final_url: uri.to_s
          }
        end

        def execute_request(uri, accept, max_bytes, verify_mode: OpenSSL::SSL::VERIFY_PEER, retried: false)
          perform_http_request(uri, accept, max_bytes, verify_mode)
        rescue OpenSSL::SSL::SSLError => e
          retry_without_verification(uri, accept, max_bytes, retried, e)
        end

        def follow_redirect(response, uri, accept, max_bytes, remaining_redirects)
          raise 'Too many redirects' if remaining_redirects <= 0

          location = response['location']
          raise 'Redirect missing location header' unless location

          new_url = absolutize(uri.to_s, location) || location
          perform_request(new_url, accept, max_bytes, remaining_redirects - 1)
        end

        def configure_timeouts(http)
          http.read_timeout = @read_timeout
          http.open_timeout = @open_timeout
        end

        def configure_ssl(http, verify_mode)
          return unless http.use_ssl?

          http.verify_mode = verify_mode
          http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
        end

        def perform_http_request(uri, accept, max_bytes, verify_mode)
          http = build_http_connection(uri, verify_mode)
          response = nil
          body = nil
          http.start do |connection|
            request = build_request(uri, accept)
            response = connection.request(request) { |res| body = read_response_body(res, max_bytes) }
          end

          [response, body]
        end

        def build_http_connection(uri, verify_mode)
          Net::HTTP.new(uri.host, uri.port).tap do |http|
            http.use_ssl = uri.scheme == 'https'
            configure_timeouts(http)
            configure_ssl(http, verify_mode)
          end
        end

        def retry_without_verification(uri, accept, max_bytes, retried, error)
          return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback && !retried

          @logger.warn "SSL error (#{error.message}), retrying without verification for #{uri}"
          execute_request(
            uri,
            accept,
            max_bytes,
            verify_mode: OpenSSL::SSL::VERIFY_NONE,
            retried: true
          )
        end

        def handle_terminal_ssl_error(uri, error)
          @logger.warn "SSL error for #{uri}: #{error.message}"
          raise error
        end

        def build_request(uri, accept)
          Net::HTTP::Get.new(uri).tap do |request|
            request['User-Agent'] = @user_agent
            request['Accept'] = accept
            request['Accept-Encoding'] = 'identity'
          end
        end

        def read_response_body(response, max_bytes)
          body = +''
          response.read_body do |chunk|
            break if body.bytesize >= max_bytes

            needed = max_bytes - body.bytesize
            body << chunk.byteslice(0, needed)
            break if body.bytesize >= max_bytes
          end
          body.force_encoding('BINARY')
          body
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
            next unless abs_url

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
            candidates << [3, guessed] if guessed
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
            next unless abs_url&.match?(%r{\Ahttps?://})

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
          return page[:final_url] if feed_like?(page[:body], page[:content_type])

          html = decode_html(page[:body])
          feed_from_html(html, page[:final_url])
        rescue StandardError => e
          @logger.warn "fetch error for #{website}: #{e.message}"
          nil
        end

        private

        def feed_from_html(html, final_url)
          find_feed_in_html(html, final_url) ||
            find_feed_in_secondary_pages(html, final_url)
        end

        def find_feed_in_html(html, final_url)
          candidates = collect_candidates(html, final_url)
          candidates.first(8).each do |candidate|
            feed_url = verify_feed(candidate)
            return feed_url if feed_url
          end
          nil
        end

        def find_feed_in_secondary_pages(html, final_url)
          secondary_page_candidates(html, final_url).first(3).each do |secondary_url|
            feed_url = probe_secondary_page(secondary_url)
            return feed_url if feed_url
          end
          nil
        end

        def probe_secondary_page(secondary_url)
          @logger.info "Probing #{secondary_url}"
          page = fetch_secondary_page(secondary_url)
          return page[:final_url] if feed_like?(page[:body], page[:content_type])

          page_html = decode_html(page[:body])
          find_feed_in_html(page_html, page[:final_url])
        rescue StandardError => e
          @logger.warn "Secondary page error for #{secondary_url}: #{e.message}"
          nil
        end

        def fetch_secondary_page(secondary_url)
          @http.fetch(secondary_url, accept: ACCEPT_HTML, max_bytes: HTML_MAX_BYTES)
        end

        def verify_feed(url)
          response = @http.fetch(url, accept: ACCEPT_FEED, max_bytes: FEED_MAX_BYTES)
          return response[:final_url] if feed_like?(response[:body], response[:content_type])

          snippet = normalize_string(response[:body]).strip
          return response[:final_url] if snippet.start_with?('{') && snippet.include?('rss')

          nil
        rescue StandardError => e
          @logger.warn "Verify error for #{url}: #{e.message}"
          nil
        end

        def collect_candidates(html, final_url)
          CandidateCollector.new(html, final_url).collect
        end

        def secondary_page_candidates(html, final_url)
          SecondaryPageCollector.new(html, final_url).collect
        end

        def feed_like?(data, content_type)
          snippet = normalize_string(data)
          preview = snippet.downcase
          ctype = (content_type || '').downcase

          return true if ctype.match?(%r{rss|atom|application/xml|text/xml}) &&
                         preview.match?(/<(rss|feed|rdf)/)

          preview.match?(/<(rss|feed|rdf)/)
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

        def absolutize(base_url, href)
          return nil if href.nil?

          cleaned = href.strip
          return nil if cleaned.empty? || cleaned.start_with?('#')

          downcased = cleaned.downcase
          return nil if downcased.start_with?('javascript:', 'data:', 'mailto:')

          base = URI.parse(base_url)
          URI.join(base, cleaned).to_s
        rescue URI::Error
          nil
        end
      end
    end
  end
end
