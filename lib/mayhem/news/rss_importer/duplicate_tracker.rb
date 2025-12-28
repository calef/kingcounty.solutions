# frozen_string_literal: true

require_relative '../../support/url_normalizer'
require_relative 'guid_extractor'

module Mayhem
  module News
    class RssImporter
      class DuplicateTracker
        include GuidExtractor

        def initialize(news_model:)
          @news_model = news_model
          @existing_posts = build_existing_post_index
          @lock = Mutex.new
        end

        def duplicate?(link_url, guid = nil)
          keys = keys_for(link_url, guid)
          return false if keys.empty?

          @lock.synchronize { keys.any? { |key| @existing_posts.key?(key) } }
        end

        def register(link_url, guid = nil)
          keys = keys_for(link_url, guid)
          return if keys.empty?

          @lock.synchronize do
            keys.each { |key| @existing_posts[key] = true }
          end
        end

        def key_for_link(link_url)
          normalized = link_url.to_s.strip
          return nil if normalized.empty?

          "link:#{normalized}"
        end

        def key_for_guid(guid_value)
          guid_text = extract_guid_text(guid_value)
          return nil unless guid_text

          "guid:#{guid_text}"
        end

        private

        def keys_for(link_url, guid)
          keys = []
          keys << key_for_link(link_url)
          keys << key_for_guid(guid)
          keys.compact
        end

        def build_existing_post_index
          @news_model.all.to_a.each_with_object({}) do |post, memo|
            next unless post.feed_content

            url = Mayhem::Support::UrlNormalizer.normalize(post.source_url)
            key = key_for_link(url)
            memo[key] = true if key

            guid_key = key_for_guid(post.rss_guid)
            memo[guid_key] = true if guid_key
          end
        end
      end
    end
  end
end
