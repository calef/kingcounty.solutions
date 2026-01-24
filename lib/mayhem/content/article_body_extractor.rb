# frozen_string_literal: true

require 'nokogiri'
require 'seldon'

module Mayhem
  module Content
    # Extracts clean article text from HTML documents.
    #
    # Designed to pull the main content from news articles and web pages
    # while filtering out navigation, scripts, and other non-content elements.
    module ArticleBodyExtractor
      module_function

      # Extracts plain text from HTML, focusing on the main article content.
      #
      # Algorithm:
      # 1. Parse HTML with Nokogiri
      # 2. Remove non-content elements (scripts, styles, nav, header, footer, etc.)
      # 3. Find the main content container with priority: article > main > body
      # 4. Extract and normalize text (collapse whitespace to single spaces)
      #
      # @param html [String, nil] Raw HTML content
      # @return [String, nil] Extracted text, or nil if HTML is nil or parsing fails
      def text_from_html(html)
        return nil unless html

        doc = Nokogiri::HTML(html)
        doc.search('script, style, nav, header, footer, noscript, iframe').remove
        fragment = doc.at_css('article') || doc.at_css('main') || doc.at_css('body') || doc
        fragment.text.strip.gsub(/\s+/, ' ')
      rescue StandardError
        nil
      end

      # Normalizes HTML content and optionally truncates to a maximum length.
      #
      # @param html [String, nil] Raw HTML content
      # @param max_chars [Integer, nil] Maximum character length (nil = no limit)
      # @return [String, nil] Normalized HTML, or nil if input is nil
      def normalized_html(html, max_chars: nil)
        return nil unless html

        cleaned = Seldon::Support::EncodingUtils.ensure_utf8(html)
        return cleaned if !max_chars || cleaned.length <= max_chars

        cleaned[0, max_chars]
      end
    end
  end
end
