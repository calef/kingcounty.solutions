# frozen_string_literal: true

require 'seldon'
require_relative '../../content/html_normalizer'
require_relative '../../front_matter/slug_generator'

module Mayhem
  module News
    class RssImporter
      include Seldon::Loggable

      class PostWriter
        include Seldon::Loggable

        MAX_FILENAME_BYTES = 255
        DEFAULT_NEWS_DIR = '_posts'

        def initialize(news_model:)
          @news_model = news_model
        end

        def write(source_title, title_text, link_url, published_time, original_html, rss_guid = nil, published: nil)
          normalized_html = Mayhem::Content::HtmlNormalizer.normalize(original_html, base_url: link_url)
          checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_html)
          date_prefix = published_time.strftime('%Y-%m-%d')
          title_slug = Mayhem::FrontMatter::SlugGenerator.filename_slug(
            title: title_text,
            link: link_url,
            date_prefix: date_prefix,
            max_bytes: MAX_FILENAME_BYTES
          )
          record_id = File.join(DEFAULT_NEWS_DIR, "#{date_prefix}-#{title_slug}.md")
          existing = find_existing_post(record_id)

          if existing&.locked?
            logger.info "Skipping update for locked post #{existing.id}"
            return :skipped_locked
          end

          if existing && existing.published == false
            logger.info "Skipping update for unpublished post #{existing.id}"
            return :skipped_unpublished
          end

          if unchanged_post?(existing, normalized_html, checksum, link_url)
            logger.debug "Skipping unchanged post #{existing.id}"
            return :skipped_unchanged
          end

          frontmatter = {
            'title' => title_text,
            'date' => published_time.iso8601,
            'organization_title' => source_title,
            'source_url' => link_url.to_s,
            'rss_guid' => rss_guid,
            'feed_content' => normalized_html,
            'feed_content_checksum' => checksum,
            'slug' => title_slug
          }
          frontmatter['published'] = false if published == false
          if existing
            frontmatter.each { |key, value| existing[key] = value }
            existing.body = ''
            existing.save!
          else
            @news_model.create!(frontmatter, body: '')
          end
          :created
        end

        private

        def find_existing_post(record_id)
          @news_model.find(record_id)
        rescue StandardError
          nil
        end

        def unchanged_post?(record, normalized_html, checksum, link_url)
          return false unless record

          existing_checksum = record.feed_content_checksum.to_s
          return true if !existing_checksum.empty? && existing_checksum == checksum

          existing_content = record.feed_content
          return false unless existing_content

          base_url = record.source_url.to_s
          base_url = link_url if base_url.empty?
          existing_normalized = Mayhem::Content::HtmlNormalizer.normalize(existing_content, base_url: base_url)
          existing_normalized == normalized_html
        rescue StandardError => e
          logger.debug "Failed to compare existing post #{record&.id}: #{e.message}"
          false
        end
      end
    end
  end
end
