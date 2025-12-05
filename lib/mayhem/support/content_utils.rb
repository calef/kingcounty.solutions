# frozen_string_literal: true

require 'nokogiri'
require 'reverse_markdown'

module Mayhem
  module Support
    module ContentUtils
      module_function

      def sanitize_html(source)
        return '' unless source

        text = source.to_s.dup
        text.force_encoding('UTF-8')
        text.scrub('')
        text.gsub(/\s+/, ' ').strip
      end

      def normalized_markdown(html_description)
        return '' if html_description.to_s.strip.empty?

        fragment = Nokogiri::HTML::DocumentFragment.parse(html_description.to_s)
        markdown = ReverseMarkdown.convert(fragment.to_html).to_s.strip
        return markdown unless markdown.include?('<') && markdown.include?('>')

        Nokogiri::HTML.fragment(fragment.to_html).text.strip
      rescue StandardError
        Nokogiri::HTML.fragment(html_description.to_s).text.strip
      end
    end
  end
end
