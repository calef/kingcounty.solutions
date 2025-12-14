# frozen_string_literal: true

require 'nokogiri'
require_relative '../support/encoding_utils'

module Mayhem
  module Content
    module ArticleBodyExtractor
      module_function

      def text_from_html(html)
        return nil unless html

        doc = Nokogiri::HTML(html)
        doc.search('script, style, nav, header, footer, noscript, iframe').remove
        fragment = doc.at_css('article') || doc.at_css('main') || doc.at_css('body') || doc
        fragment.text.strip.gsub(/\s+/, ' ')
      rescue StandardError
        nil
      end

      def sanitized_html(html, max_chars: nil)
        return nil unless html

        cleaned = Mayhem::Support::EncodingUtils.ensure_utf8(html)
        return cleaned if !max_chars || cleaned.length <= max_chars

        cleaned[0, max_chars]
      end
    end
  end
end
