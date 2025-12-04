# frozen_string_literal: true

require 'nokogiri'
require_relative 'article_body_selectors'
require_relative '../feed_discovery'

module Mayhem
  module Support
    class ContentFetcher
      def initialize(
        http_client:,
        logger:,
        selectors: ArticleBodySelectors::SELECTORS,
        accept: Mayhem::FeedDiscovery::ACCEPT_HTML,
        max_bytes: Mayhem::FeedDiscovery::HTML_MAX_BYTES
      )
        @http_client = http_client
        @logger = logger
        @selectors = selectors
        @accept = accept
        @max_bytes = max_bytes
      end

      def fetch(url)
        page = @http_client.fetch(url, accept: @accept, max_bytes: @max_bytes)
        document = Nokogiri::HTML(page[:body])
        strip_unwanted_nodes(document)
        body_node = document.at_css('body')
        snippet = extract_snippet(document) || body_node&.inner_html
        cleaned_snippet = sanitize_snippet(snippet)
        cleaned_snippet = sanitize_snippet(body_node&.inner_html) if cleaned_snippet.strip.empty? && body_node
        cleaned_snippet = sanitize_html(page[:body]) if cleaned_snippet.strip.empty?

        { html: cleaned_snippet, canonical_url: page[:final_url] }
      end

      private

      def extract_snippet(document)
        @selectors.each do |selector|
          node = document.at_css(selector)
          next unless node

          snippet = node.inner_html.to_s.strip
          return snippet unless snippet.empty?
        end

        fallback = document.at_css('main') || document.at_css('#main') || document.at_css('#content')
        fallback&.inner_html&.strip
      end

      def strip_unwanted_nodes(document)
        document.css('script').each do |node|
          type = node['type'].to_s.downcase
          next if type.include?('ld+json') || type.include?('json')

          node.remove
        end
        document.css('style, noscript, svg, footer, nav, button, iframe, link').remove
        document.xpath('//comment()').remove
      end

      def sanitize_snippet(fragment_html)
        html = fragment_html.to_s
        return '' if html.strip.empty?

        fragment = Nokogiri::HTML::DocumentFragment.parse(html)
        strip_empty_tags(fragment)
        fragment.xpath('//comment()').remove
        sanitize_html(fragment.to_html)
      end

      def strip_empty_tags(fragment)
        loop do
          empties = fragment.css('*').select do |node|
            node.element? && node.inner_html.to_s.strip.empty?
          end
          break if empties.empty?

          empties.each(&:remove)
        end
      end

      def sanitize_html(source)
        return '' unless source

        text = source.to_s.dup
        text.force_encoding('UTF-8')
        text.scrub('')
        text.gsub(/\s+/, ' ').strip
      end
    end
  end
end
