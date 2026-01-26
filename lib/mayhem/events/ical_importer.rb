# frozen_string_literal: true

require 'date'
require 'icalendar'
require 'nokogiri'
require 'seldon'
require_relative '../errors'
require_relative '../feed/discovery'
require_relative '../content/content_fetcher'
require_relative '../content/content_utils'
require_relative '../content/html_normalizer'
require_relative '../models/event'
require_relative '../models/organization'
require_relative '../threading/pool_executor'

module Mayhem
  module Events
    class IcalImporter
      include Seldon::Loggable

      MAX_FILENAME_BYTES = 255
      DEFAULT_MAX_WORKERS = begin
        Integer(ENV.fetch('ICAL_WORKERS', '6'))
      rescue ArgumentError, KeyError
        6
      end

      ACCEPT_HEADER = Mayhem::FeedDiscovery::ACCEPT_FEED

      def initialize(
        http_client: nil,
        workers: DEFAULT_MAX_WORKERS,
        time_source: -> { Time.now }
      )
        @http_client = http_client || Seldon::Support::HttpClient.new(
          cookie_jar: Seldon::Support::CookieJar.new
        )
        @content_fetcher = Mayhem::Content::ContentFetcher.new(http_client: @http_client)
        @time_source = time_source
        @workers = [workers, 1].max
        @processed_orgs = 0
        @stats = Hash.new(0)
        @existing_urls = {}
        @future_limit = nil
        @existing_lock = Mutex.new
        @stats_lock = Mutex.new
        @processed_lock = Mutex.new
        @executor = Threading::PoolExecutor.new(workers: @workers)
      end

      def run
        @existing_urls = build_existing_event_index
        @executor.run(Mayhem::Models::Organization.all) do |org_record|
          process_org_record(org_record)
        end
        log_summary
      end

      private

      def build_existing_event_index
        index = {}
        Mayhem::Models::Event.all.each do |event|
          url = normalized_link(event.source_url, nil)
          index[url] = event if url
        end
        index
      end

      def log_summary
        stats_snapshot = nil
        @stats_lock.synchronize { stats_snapshot = @stats.dup }
        processed = processed_org_count
        logger.info(
          "Events import summary: organizations=#{processed} " \
          "created=#{stats_snapshot[:created]} duplicates=#{stats_snapshot[:duplicate]} " \
          "past=#{stats_snapshot[:past_event]} far_future=#{stats_snapshot[:far_future_event]} " \
          "unchanged=#{stats_snapshot[:unchanged]} fetch_failed=#{stats_snapshot[:fetch_failed]} " \
          "write_failed=#{stats_snapshot[:write_failed]} parse_failed=#{stats_snapshot[:parse_failed]}"
        )
      end

      def record_stat(key, stats)
        raise ArgumentError, 'stats hash is required for record_stat' unless stats

        stats[key] += 1
        @stats_lock.synchronize { @stats[key] += 1 }
      end

      def log_org_summary(source_title, source_url, stats)
        return unless source_title && source_url

        logger.info(
          "Processed '#{source_title}' (#{source_url}): #{org_summary_line(stats)}"
        )
      end

      def org_summary_line(stats)
        labels = {
          created: 'created',
          duplicate: 'duplicates',
          past_event: 'past_event',
          far_future_event: 'far_future_event',
          missing_title: 'missing_title',
          missing_start_date: 'missing_date',
          missing_url: 'missing_url',
          fetch_failed: 'fetch_failed',
          parse_failed: 'parse_failed',
          write_failed: 'write_failed',
          unpublished: 'unpublished',
          unchanged: 'unchanged',
          locked: 'locked'
        }
        parts = labels.map do |key, label|
          value = stats[key]
          "#{label}=#{value}" if value&.positive?
        end.compact
        parts.empty? ? 'no_changes' : parts.join(', ')
      end

      def process_org_record(org_record)
        increment_processed_orgs
        stats = Hash.new(0)
        summary = process_organization(org_record, stats)
        log_org_summary(summary[:title], summary[:source], stats) if summary
      end

      def increment_processed_orgs
        @processed_lock.synchronize { @processed_orgs += 1 }
      end

      def processed_org_count
        @processed_lock.synchronize { @processed_orgs }
      end

      def process_organization(org_record, stats)
        return unless org_record

        ical_url = org_record.events_ical_url.to_s.strip
        return if ical_url.empty?

        source_title = org_record.title
        website_url = org_record.website_url

        import_from_url(ical_url, source_title, website_url, stats)
        { title: source_title, source: ical_url }
      end

      def import_from_url(url, source_title, website, stats)
        page = @http_client.fetch(url, accept: ACCEPT_HEADER)
        import_calendar(page[:body], source_title, website, stats)
      rescue Seldon::Support::HttpClient::HttpError,
             Seldon::Support::HttpClient::TooManyRequestsError,
             Seldon::Support::HttpClient::ServiceUnavailableError,
             *Mayhem::NetworkError::EXCEPTIONS => e
        record_stat(:fetch_failed, stats)
        logger.warn "Failed to fetch events for #{source_title} (#{url}): #{e.message}"
      end

      def import_calendar(body, source_title, website, stats)
        return if body.to_s.strip.empty?

        calendars = Icalendar::Calendar.parse(body)
        events = calendars.flat_map(&:events)
        events.each { |event| create_event(event, source_title, website, stats) }
      rescue Icalendar::Parser::ParseError => e
        record_stat(:parse_failed, stats)
        logger.error "Failed to parse iCal for #{source_title}: #{e.message}"
      end

      def create_event(event, source_title, website, stats)
        event_data = extract_event_data(event, website)
        return unless event_basics_valid?(event_data, stats)

        url_result = resolve_event_urls(event_data[:source_url], website, stats)
        return unless url_result

        content_result = prepare_event_content(url_result, event_data)
        existing = find_existing_event(url_result[:canonical_url])

        return handle_existing_event(existing, url_result, content_result[:checksum], stats) if existing

        persist_new_event(event_data, url_result, content_result, source_title, stats)
      rescue FMRepo::Error, Errno::ENOENT, Errno::EACCES, IOError => e
        logger.warn "Failed to persist event #{event_data&.dig(:summary) || '<untitled>'}: #{e.message}"
        record_stat(:write_failed, stats)
      end

      def extract_event_data(event, website)
        {
          summary: normalize_summary(event.summary),
          start_time: resolve_time(event.dtstart),
          end_time: resolve_time(event.dtend),
          source_url: normalized_link(event.url, website),
          location: Seldon::Support::EncodingUtils.ensure_utf8(event_location(event)),
          description: event.description,
          dtstart: event.dtstart
        }
      end

      def event_basics_valid?(data, stats)
        return skip_event(reason: :missing_title, reason_detail: data[:dtstart], stats: stats) unless data[:summary]

        return skip_event(reason: :missing_start_date, reason_detail: data[:summary], stats: stats) unless data[:start_time]

        return skip_event(reason: :past_event, reason_detail: data[:summary], stats: stats) if data[:start_time] < current_time

        return skip_event(reason: :far_future_event, reason_detail: data[:summary], stats: stats) if data[:start_time] > future_limit

        return skip_event(reason: :missing_url, reason_detail: data[:summary], stats: stats) unless data[:source_url]

        true
      end

      def resolve_event_urls(source_url, website, stats)
        fetch_result = fetch_event_body(source_url, stats)
        canonical_url = determine_canonical_url(fetch_result, source_url, website)

        if canonical_url.to_s.strip.empty?
          skip_event(reason: :missing_url, reason_detail: source_url, stats: stats)
          return nil
        end

        {
          source_url: source_url,
          canonical_url: canonical_url,
          fetch_result: fetch_result
        }
      end

      def determine_canonical_url(fetch_result, source_url, website)
        canonical = fetch_result && fetch_result[:canonical_url]
        canonical = canonicalized_url(canonical, website)
        canonical ||= canonicalized_url(source_url, website)
        canonical = source_url if canonical.to_s.strip.empty?
        canonical
      end

      def prepare_event_content(url_result, event_data)
        raw_html = url_result[:fetch_result] && url_result[:fetch_result][:html]
        description_html = Seldon::Support::EncodingUtils.ensure_utf8(raw_html)

        if description_html.to_s.strip.empty?
          description_html = Mayhem::Content::ContentUtils.sanitize_html(event_data[:description])
          description_html = Seldon::Support::EncodingUtils.ensure_utf8(description_html)
        end

        description_html = Seldon::Support::EncodingUtils.ensure_utf8(description_html)
        normalized = Mayhem::Content::HtmlNormalizer.normalize(description_html, base_url: url_result[:canonical_url])
        checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized)

        { normalized_description: normalized, checksum: checksum }
      end

      def find_existing_event(canonical_url)
        normalized_canonical = normalized_link(canonical_url, nil)
        @existing_lock.synchronize { @existing_urls[normalized_canonical] }
      end

      def handle_existing_event(existing, url_result, checksum, stats)
        register_event_url(url_result[:canonical_url], existing)
        register_event_url(url_result[:source_url], existing) unless url_result[:canonical_url] == url_result[:source_url]

        return skip_event(reason: :locked, reason_detail: url_result[:canonical_url], stats: stats) if existing.locked?

        existing_checksum = compute_existing_checksum(existing, url_result[:canonical_url])
        return skip_event(reason: :unchanged, reason_detail: url_result[:canonical_url], stats: stats) if existing_checksum && existing_checksum == checksum

        skip_event(reason: :duplicate, reason_detail: url_result[:canonical_url], stats: stats)
      end

      def compute_existing_checksum(existing, canonical_url)
        if existing.respond_to?(:feed_content_checksum) && existing.feed_content_checksum
          existing.feed_content_checksum
        elsif existing.respond_to?(:feed_content) && existing.feed_content
          existing_normalized = Mayhem::Content::HtmlNormalizer.normalize(
            existing.feed_content,
            base_url: canonical_url
          )
          Mayhem::Content::HtmlNormalizer.checksum(existing_normalized)
        end
      end

      def persist_new_event(event_data, url_result, content_result, source_title, stats)
        front_matter = build_event_front_matter(event_data, url_result, content_result, source_title)
        new_event = Mayhem::Models::Event.create!(front_matter, body: '')

        record_stat(:created, stats)
        register_event_url(url_result[:canonical_url], new_event)
        register_event_url(url_result[:source_url], new_event) unless url_result[:canonical_url] == url_result[:source_url]
      end

      def build_event_front_matter(event_data, url_result, content_result, source_title)
        end_time = event_data[:end_time] || event_data[:start_time]

        front_matter = {
          'title' => Seldon::Support::EncodingUtils.ensure_utf8(event_data[:summary]),
          'organization_title' => Seldon::Support::EncodingUtils.ensure_utf8(source_title),
          'start_date' => event_data[:start_time].iso8601,
          'end_date' => end_time.iso8601,
          'location' => event_data[:location],
          'source_url' => url_result[:canonical_url]
        }

        fetch_result = url_result[:fetch_result]
        front_matter['published'] = false if fetch_result && fetch_result[:not_found]

        unless content_result[:normalized_description].to_s.strip.empty?
          front_matter['feed_content'] = content_result[:normalized_description]
          front_matter['feed_content_checksum'] = content_result[:checksum]
        end

        front_matter
      end

      def skip_event(reason:, stats:, reason_detail: nil)
        debug_detail = reason_detail ? " (#{reason_detail})" : ''
        logger.debug "Skipping event: #{reason}#{debug_detail}"
        record_stat(reason, stats)
        nil
      end

      # Normalizes a URL for consistent storage and lookup.
      #
      # @param link [String, nil] The URL to normalize
      # @param website [String, nil] Base URL for resolving relative links.
      #   Pass nil only when the link is known to be absolute (e.g., canonical
      #   URLs or source_url from saved events). Relative URLs with nil base
      #   will log a warning and return nil.
      # @return [String, nil] Normalized URL, or nil if input is empty/invalid
      def normalized_link(link, website)
        return nil if link.to_s.strip.empty?

        link_str = link.to_s
        if website.nil? && relative_url?(link_str)
          logger.warn "normalized_link: Cannot normalize relative URL without base URL. Expected absolute URL but got: #{link_str}"
          return nil
        end

        Seldon::Support::UrlNormalizer.normalize(link_str, base: website)
      end

      def relative_url?(url)
        # Matches RFC 3986-style schemes with flexibility for practical use:
        # - Allows schemes starting with letter or digit (though RFC mandates letter)
        # - Requires at least 2 characters before colon (avoids Windows drive letters)
        # - Matches both hierarchical (http://) and non-hierarchical (mailto:) schemes
        !url.match?(/\A[a-z0-9][a-z0-9+.-]+:/i)
      end

      def canonicalized_url(url, website)
        return nil if url.to_s.strip.empty?

        normalized = normalized_link(url, website)
        return nil if normalized.to_s.strip.empty?

        Mayhem::Content::HtmlNormalizer.canonicalize_url(normalized)
      end

      def register_event_url(url, event = nil)
        normalized = normalized_link(url, nil)
        return if normalized.to_s.strip.empty?

        @existing_lock.synchronize { @existing_urls[normalized] = event || true }
      end

      def event_registered?(url)
        normalized = normalized_link(url, nil)
        return false if normalized.to_s.strip.empty?

        @existing_lock.synchronize { @existing_urls.key?(normalized) }
      end

      def event_location(event)
        event.location.to_s.strip
      end

      def normalize_summary(summary)
        return unless summary

        text = summary.to_s.strip
        text.empty? ? nil : text
      end

      def resolve_time(field)
        value = value_object(field)
        return value if value.is_a?(Time)

        value.to_time if value.respond_to?(:to_time)
      rescue ArgumentError, TypeError
        nil
      end

      def value_object(field)
        return unless field

        return field if field.is_a?(Date) || field.is_a?(Time) || field.is_a?(DateTime)

        field.value if field.respond_to?(:value)
      end

      def fetch_event_body(url, stats)
        return unless url

        @content_fetcher.fetch(url)
      rescue Seldon::Support::HttpClient::NotFoundError => e
        record_stat(:fetch_failed, stats)
        logger.warn "Source returned 404 for #{url}: #{e.message}"
        { html: '', canonical_url: url, not_found: true }
      rescue Seldon::Support::HttpClient::HttpError,
             Seldon::Support::HttpClient::TooManyRequestsError,
             Seldon::Support::HttpClient::ServiceUnavailableError,
             *Mayhem::NetworkError::EXCEPTIONS => e
        record_stat(:fetch_failed, stats)
        logger.warn "Failed to fetch more info for #{url}: #{e.message}"
        nil
      end

      def current_time
        @time_source.call
      end

      def future_limit
        @future_limit ||= begin
          now = current_time
          (now.to_datetime >> 3).to_time
        end
      end
    end

    class IcalImporterCLI
      include Seldon::Loggable

      def self.run
        new.run
      end

      def initialize(
        http_client: nil
      )
        @http_client = http_client || Seldon::Support::HttpClient.new(
          cookie_jar: Seldon::Support::CookieJar.new
        )
      end

      def run
        importer = IcalImporter.new(http_client: @http_client)
        importer.run
      rescue Interrupt
        logger.info 'Interrupted; exiting events import'
      end
    end
  end
end
