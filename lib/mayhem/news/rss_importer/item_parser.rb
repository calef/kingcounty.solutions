# frozen_string_literal: true

require 'rss'
require 'time'
require_relative 'guid_extractor'

module Mayhem
  module News
    class RssImporter
      class ItemParser
        include Mayhem::Loggable
        include GuidExtractor

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

        def content_html(item)
          return item.content_encoded if item.respond_to?(:content_encoded) && item.content_encoded
          return item.description if item.respond_to?(:description) && item.description
          return item.summary if item.respond_to?(:summary) && item.summary

          content = item.content if item.respond_to?(:content)
          return content.content if content.respond_to?(:content) && content.content

          content if content.is_a?(String)
        rescue StandardError => e
          logger.warn "Failed to read content for #{item.link || item.title}: #{e.message}"
          nil
        end

        def title_text(item)
          title = item.title if item.respond_to?(:title)
          return title.content if title.respond_to?(:content)

          title.to_s
        rescue StandardError
          link_url(item) || 'Untitled'
        end

        def link_url(item)
          if item.respond_to?(:link)
            link = item.link
            return link.href if link.respond_to?(:href)
            return link.to_s unless link.is_a?(RSS::Atom::Feed::Link)
          end
          if item.respond_to?(:links) && item.links.respond_to?(:each)
            alternate = item.links.find { |link| link.respond_to?(:rel) && link.rel == 'alternate' }
            return alternate.href if alternate.respond_to?(:href)

            first = item.links.first
            return first.href if first.respond_to?(:href)
          end
          item.respond_to?(:url) ? item.url.to_s : nil
        rescue StandardError => e
          title = item.respond_to?(:title) ? item.title : 'unknown item'
          logger.warn "Failed to read link for #{title}: #{e.message}"
          nil
        end

        def guid(item)
          return extract_guid_text(item.guid) if item.respond_to?(:guid) && item.guid
          return extract_guid_text(item.id) if item.respond_to?(:id) && item.id

          nil
        rescue StandardError => e
          title = item.respond_to?(:title) ? item.title : 'unknown item'
          logger.warn "Failed to read guid for #{title}: #{e.message}"
          nil
        end
      end
    end
  end
end
