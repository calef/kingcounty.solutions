# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'openssl'
require_relative '../../support/http_client'
require_relative '../../support/url_normalizer'

module Mayhem
  module News
    class RssImporter
      include Mayhem::Loggable

      class ItemProcessor
        include Mayhem::Loggable

        def initialize(item_parser:, canonicalizer:, content_fetcher:, duplicate_tracker:, post_writer:, max_item_age_days:)
          @item_parser = item_parser
          @canonicalizer = canonicalizer
          @content_fetcher = content_fetcher
          @duplicate_tracker = duplicate_tracker
          @post_writer = post_writer
          @max_item_age_days = max_item_age_days
        end

        def process(item, source_title, source_record, stats)
          link_url = @item_parser.link_url(item)
          normalized = Mayhem::Support::UrlNormalizer.normalize(link_url, base: source_record&.website_url)
          normalized = @canonicalizer.canonical_link(normalized)
          if normalized.to_s.strip.empty?
            stats.increment(:missing_link)
            return
          end
          guid_value = @item_parser.guid(item)

          title_text = @item_parser.title_text(item).to_s.strip
          if title_text.empty?
            stats.increment(:missing_title)
            return
          end

          published_time = @item_parser.published_at(item)
          unless published_time
            stats.increment(:missing_publish_date)
            return
          end

          if stale_item?(published_time)
            stats.increment(:stale)
            return
          end

          original_html = @item_parser.content_html(item).to_s.strip
          body_data = nil
          force_unpublished = false
          if normalized && (original_html.empty? || @canonicalizer.redirect_host?(normalized))
            body_data = fetch_article_body(normalized)
            force_unpublished = true if body_data && body_data[:not_found]
            fetched_html = body_data[:html].to_s.strip
            original_html = fetched_html if original_html.empty?
          end
          if body_data && body_data[:canonical_url]
            updated = @canonicalizer.canonical_link(normalized, html_canonical: body_data[:canonical_url])
            if updated && updated != normalized
              normalized = updated
              if @duplicate_tracker.duplicate?(normalized, guid_value)
                stats.increment(:duplicates)
                return
              end
            end
          end
          if original_html.empty?
            if force_unpublished
              stats.increment(:not_found)
            else
              stats.increment(:empty_content)
              return
            end
          end

          if @duplicate_tracker.duplicate?(normalized, guid_value)
            stats.increment(:duplicates)
            return
          end

          publish_flag = force_unpublished ? false : nil
          result = @post_writer.write(
            source_title,
            title_text,
            normalized,
            published_time,
            original_html,
            guid_value,
            published: publish_flag
          )
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
          @duplicate_tracker.register(normalized, guid_value) if result
          result
        end

        private

        def stale_item?(published_time)
          cutoff = Time.now - (@max_item_age_days * 24 * 60 * 60)
          published_time < cutoff
        end

        def fetch_article_body(url)
          return { html: '', canonical_url: nil } unless url

          @content_fetcher.fetch(url)
        rescue Mayhem::Support::HttpClient::NotFoundError => e
          logger.warn "Article URL returned 404 (#{url}): #{e.message}"
          { html: '', canonical_url: url, not_found: true }
        rescue OpenURI::HTTPError, OpenSSL::SSL::SSLError, SocketError,
               Net::OpenTimeout, Net::ReadTimeout => e
          logger.warn "Failed to fetch article body (#{url}): #{e.message}"
          { html: '', canonical_url: nil }
        rescue StandardError => e
          logger.error "Unexpected error scraping #{url}: #{e.message}"
          { html: '', canonical_url: nil }
        end
      end
    end
  end
end
