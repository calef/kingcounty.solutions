# frozen_string_literal: true

require 'seldon'
require_relative '../../errors'

module Mayhem
  module News
    class RssImporter
      include Seldon::Loggable

      class ItemProcessor
        include Seldon::Loggable

        def initialize(item_parser:, canonicalizer:, content_fetcher:, duplicate_tracker:, post_writer:, max_item_age_days:)
          @item_parser = item_parser
          @canonicalizer = canonicalizer
          @content_fetcher = content_fetcher
          @duplicate_tracker = duplicate_tracker
          @post_writer = post_writer
          @max_item_age_days = max_item_age_days
        end

        def process(item, source_title, source_record, stats)
          item_data = extract_item_data(item, source_record)
          return unless required_fields_valid?(item_data, stats)
          return if already_registered?(item_data, stats)

          content_result = fetch_content_if_needed(item_data)
          item_data[:normalized_url] = update_canonical_url(item_data, content_result, stats)
          return unless item_data[:normalized_url]

          return unless content_valid?(content_result, stats)

          write_post_and_record_result(source_title, item_data, content_result, stats)
        end

        private

        def extract_item_data(item, source_record)
          link_url = @item_parser.link_url(item)
          normalized = Seldon::Support::UrlNormalizer.normalize(link_url, base: source_record&.website_url)
          normalized = @canonicalizer.canonical_link(normalized)

          {
            normalized_url: normalized,
            guid: @item_parser.guid(item),
            title: @item_parser.title_text(item).to_s.strip,
            published_at: @item_parser.published_at(item),
            original_html: @item_parser.content_html(item).to_s.strip
          }
        end

        def required_fields_valid?(item_data, stats)
          if item_data[:normalized_url].to_s.strip.empty?
            stats.increment(:missing_link)
            return false
          end

          if item_data[:title].empty?
            stats.increment(:missing_title)
            return false
          end

          unless item_data[:published_at]
            stats.increment(:missing_publish_date)
            return false
          end

          if stale_item?(item_data[:published_at])
            stats.increment(:stale)
            return false
          end

          true
        end

        def fetch_content_if_needed(item_data)
          normalized = item_data[:normalized_url]
          original_html = item_data[:original_html]

          needs_fetch = normalized && (original_html.empty? || @canonicalizer.redirect_host?(normalized))
          return { html: original_html, fetched: false } unless needs_fetch

          body_data = fetch_article_body(normalized)
          fetched_html = body_data[:html].to_s.strip

          {
            html: original_html.empty? ? fetched_html : original_html,
            canonical_url: body_data[:canonical_url],
            not_found: body_data[:not_found],
            fetched: true
          }
        end

        def update_canonical_url(item_data, content_result, stats)
          return item_data[:normalized_url] unless content_result[:canonical_url]

          updated = @canonicalizer.canonical_link(
            item_data[:normalized_url],
            html_canonical: content_result[:canonical_url]
          )

          return item_data[:normalized_url] unless updated && updated != item_data[:normalized_url]

          if @duplicate_tracker.duplicate?(updated, item_data[:guid])
            stats.increment(:duplicates)
            return nil
          end

          updated
        end

        def content_valid?(content_result, stats)
          return true unless content_result[:html].to_s.strip.empty?

          if content_result[:not_found]
            stats.increment(:not_found)
            true
          else
            stats.increment(:empty_content)
            false
          end
        end

        def already_registered?(item_data, stats)
          if @duplicate_tracker.duplicate?(item_data[:normalized_url], item_data[:guid])
            stats.increment(:duplicates)
            true
          else
            false
          end
        end

        def write_post_and_record_result(source_title, item_data, content_result, stats)
          publish_flag = content_result[:not_found] ? false : nil
          html_content = content_result[:html].to_s.strip.empty? ? '' : content_result[:html]

          result = @post_writer.write(
            source_title,
            item_data[:title],
            item_data[:normalized_url],
            item_data[:published_at],
            html_content,
            item_data[:guid],
            published: publish_flag
          )

          record_write_result(result, stats)
          @duplicate_tracker.register(item_data[:normalized_url], item_data[:guid]) if result
          result
        end

        def record_write_result(result, stats)
          case result
          when :created
            stats.increment(:created)
          when :skipped_unpublished
            stats.increment(:skipped_unpublished)
          when :skipped_unchanged
            stats.increment(:unchanged)
          when :skipped_locked
            stats.increment(:locked)
          end
        end

        def stale_item?(published_time)
          cutoff = Time.now - (@max_item_age_days * 24 * 60 * 60)
          published_time < cutoff
        end

        def fetch_article_body(url)
          return { html: '', canonical_url: nil } unless url

          @content_fetcher.fetch(url)
        rescue Seldon::Support::HttpClient::NotFoundError => e
          logger.warn "Article URL returned 404 (#{url}): #{e.message}"
          { html: '', canonical_url: url, not_found: true }
        rescue Seldon::Support::HttpClient::HttpError,
               Seldon::Support::HttpClient::TooManyRequestsError,
               *Mayhem::NetworkError::EXCEPTIONS => e
          logger.warn "Failed to fetch article body (#{url}): #{e.message}"
          { html: '', canonical_url: nil }
        rescue StandardError => e
          # Catch-all for unexpected errors to ensure batch processing continues.
          # Logged at error level to ensure visibility.
          logger.error "Unexpected error scraping #{url}: #{e.message}"
          { html: '', canonical_url: nil }
        end
      end
    end
  end
end
