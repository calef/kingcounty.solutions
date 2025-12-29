# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'icalendar'
require 'nokogiri'
require_relative '../logging'
require_relative '../front_matter/document'
require_relative '../support/http_client'
require_relative '../feed/discovery'
require_relative '../front_matter/slug_generator'
require_relative '../support/url_normalizer'
require_relative '../content/content_fetcher'
require_relative '../support/encoding_utils'
require_relative '../content/content_utils'
require_relative '../front_matter/publish_guard'
require_relative '../content/html_normalizer'
require_relative '../models/organization'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Events
    class IcalImporter
      include Mayhem::Loggable

      DEFAULT_EVENTS_DIR = '_events'
      MAX_FILENAME_BYTES = 255
      DEFAULT_MAX_WORKERS = begin
        Integer(ENV.fetch('ICAL_WORKERS', '6'))
      rescue StandardError
        6
      end

      ACCEPT_HEADER = Mayhem::FeedDiscovery::ACCEPT_FEED
      attr_reader :events_dir

      def initialize(
        events_dir: DEFAULT_EVENTS_DIR,
        http_client: nil,
        workers: DEFAULT_MAX_WORKERS,
        time_source: -> { Time.now }
      )
        @events_dir = events_dir
        @http_client = http_client || Mayhem::Support::HttpClient.new
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
      end

      def run
        ensure_events_dir
        @existing_urls = build_existing_event_index
        queue = Queue.new
        Dir.glob(File.join(org_dir, '*.md')).each { |org_path| queue << org_path }

        threads = Array.new(@workers) do
          Thread.new do
            loop do
              org_path = queue.pop(true)
              process_org_path(org_path)
            rescue ThreadError
              break
            end
          end
        end
        threads.each(&:join)
        log_summary
      end

      private

      def ensure_events_dir
        FileUtils.mkdir_p(@events_dir)
      end

      def build_existing_event_index
        index = {}
        Dir.glob(File.join(@events_dir, '*.md')).each do |path|
          document = Mayhem::FrontMatter::Document.load(path)
          next unless document

          front_matter = document.front_matter
          url = normalized_link(front_matter['source_url'], nil)
          index[url] = true if url
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
        stats[key] += 1 if stats
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

      def process_org_path(org_path)
        increment_processed_orgs
        stats = Hash.new(0)
        summary = process_organization(org_path, stats)
        log_org_summary(summary[:title], summary[:source], stats) if summary
      end

      def increment_processed_orgs
        @processed_lock.synchronize { @processed_orgs += 1 }
      end

      def processed_org_count
        @processed_lock.synchronize { @processed_orgs }
      end

      def process_organization(path, stats)
        document = Mayhem::FrontMatter::Document.load(path)
        return unless document

        ical_url = document.front_matter['events_ical_url'].to_s.strip
        return if ical_url.empty?

        source_title = document.front_matter['title'] || File.basename(path, '.md')
        website_url = document.front_matter['website_url']

        import_from_url(ical_url, source_title, website_url, stats)
        { title: source_title, source: ical_url }
      end

      def import_from_url(url, source_title, website, stats)
        page = @http_client.fetch(url, accept: ACCEPT_HEADER)
        import_calendar(page[:body], source_title, website, stats)
      rescue StandardError => e
        record_stat(:fetch_failed, stats)
        logger.warn "Failed to fetch events for #{source_title} (#{url}): #{e.message}"
      end

      def import_calendar(body, source_title, website, stats)
        return if body.to_s.strip.empty?

        calendars = Icalendar::Calendar.parse(body)
        events = calendars.flat_map(&:events)
        events.each { |event| create_event(event, source_title, website, stats) }
      rescue StandardError => e
        record_stat(:parse_failed, stats)
        logger.error "Failed to parse iCal for #{source_title}: #{e.message}"
      end

      def create_event(event, source_title, website, stats)
        summary = normalize_summary(event.summary)
        return skip_event(reason: :missing_title, reason_detail: event.dtstart, stats: stats) unless summary

        start_time = resolve_time(event.dtstart)
        return skip_event(reason: :missing_start_date, reason_detail: summary, stats: stats) unless start_time
        return skip_event(reason: :past_event, reason_detail: summary, stats: stats) if start_time < current_time
        return skip_event(reason: :far_future_event, reason_detail: summary, stats: stats) if start_time > future_limit

        source_url = normalized_link(event.url, website)
        return skip_event(reason: :missing_url, reason_detail: summary, stats: stats) unless source_url
        return skip_event(reason: :duplicate, reason_detail: source_url, stats: stats) if event_registered?(source_url)

        fetch_result = fetch_event_body(source_url, stats)
        raw_html = fetch_result && fetch_result[:html]
        canonical_url = fetch_result && fetch_result[:canonical_url]
        canonical_url = normalized_link(canonical_url, website) if canonical_url
        canonical_url = source_url if canonical_url.to_s.strip.empty?
        return skip_event(reason: :missing_url, reason_detail: summary, stats: stats) if canonical_url.to_s.strip.empty?

        if event_registered?(canonical_url)
          return skip_event(reason: :duplicate, reason_detail: canonical_url,
                            stats: stats)
        end

        location = Mayhem::Support::EncodingUtils.ensure_utf8(event_location(event))
        end_time = resolve_time(event.dtend) || start_time
        start_prefix = start_time.strftime('%Y-%m-%d')
        start_value = start_time.iso8601
        end_value = end_time.iso8601

        slug = Mayhem::FrontMatter::SlugGenerator.filename_slug(
          title: summary,
          link: canonical_url || source_title,
          date_prefix: start_prefix,
          max_bytes: MAX_FILENAME_BYTES
        )
        filename = File.join(@events_dir, "#{start_prefix}-#{slug}.md")

        description_html = Mayhem::Support::EncodingUtils.ensure_utf8(raw_html)
        description_html = Mayhem::Content::ContentUtils.sanitize_html(event.description) if description_html.to_s.strip.empty?
        description_html = Mayhem::Support::EncodingUtils.ensure_utf8(description_html)
        normalized_description = Mayhem::Content::HtmlNormalizer.normalize(description_html, base_url: canonical_url)
        checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_description)

        if locked_entry?(filename)
          register_event_url(canonical_url)
          register_event_url(source_url) unless canonical_url == source_url
          return skip_event(reason: :locked, reason_detail: filename, stats: stats)
        end

        front_matter = {
          'title' => Mayhem::Support::EncodingUtils.ensure_utf8(summary),
          'organization_title' => Mayhem::Support::EncodingUtils.ensure_utf8(source_title),
          'start_date' => start_value,
          'end_date' => end_value,
          'location' => location,
          'source_url' => canonical_url
        }
        front_matter['published'] = false if fetch_result && fetch_result[:not_found]
        unless normalized_description.to_s.strip.empty?
          front_matter['feed_content'] = normalized_description
          front_matter['feed_content_checksum'] = checksum
        end
        body_content = ''
        if event_content_unchanged?(filename, normalized_description, checksum, canonical_url)
          register_event_url(canonical_url)
          register_event_url(source_url) unless canonical_url == source_url
          return skip_event(reason: :unchanged, reason_detail: filename, stats: stats)
        end
        document = Mayhem::FrontMatter::Document.new(
          path: filename,
          front_matter: front_matter,
          body: body_content
        )
        return skip_event(reason: :unpublished, reason_detail: filename, stats: stats) if Mayhem::FrontMatter::PublishGuard.unpublished?(filename)

        document.save
        record_stat(:created, stats)
        register_event_url(canonical_url)
        register_event_url(source_url) unless canonical_url == source_url
      rescue StandardError => e
        logger.warn "Failed to persist event #{summary || '<untitled>'}: #{e.message}"
        record_stat(:write_failed, stats)
      end

      def skip_event(reason:, reason_detail: nil, stats: nil)
        debug_detail = reason_detail ? " (#{reason_detail})" : ''
        logger.debug "Skipping event: #{reason}#{debug_detail}"
        record_stat(reason, stats)
        nil
      end

      def normalized_link(link, website)
        Mayhem::Support::UrlNormalizer.normalize(link, base: website)
      end

      def register_event_url(url)
        normalized = normalized_link(url, nil)
        return if normalized.to_s.strip.empty?

        @existing_lock.synchronize { @existing_urls[normalized] = true }
      end

      def event_registered?(url)
        normalized = normalized_link(url, nil)
        return false if normalized.to_s.strip.empty?

        @existing_lock.synchronize { @existing_urls.key?(normalized) }
      end

      def event_content_unchanged?(filename, normalized_html, checksum, canonical_url)
        return false unless File.exist?(filename)
        return false if normalized_html.to_s.strip.empty?

        document = Mayhem::FrontMatter::Document.load(filename)
        return false unless document

        front_matter = document.front_matter
        existing_checksum = front_matter['feed_content_checksum'].to_s
        return true if !existing_checksum.empty? && existing_checksum == checksum

        existing_content = front_matter['feed_content']
        return false unless existing_content

        base_url = front_matter['source_url'].to_s
        base_url = canonical_url if base_url.empty?
        existing_normalized = Mayhem::Content::HtmlNormalizer.normalize(existing_content, base_url: base_url)
        existing_normalized == normalized_html
      rescue StandardError => e
        logger.debug "Failed to compare existing event #{filename}: #{e.message}"
        false
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
      rescue StandardError
        nil
      end

      def value_object(field)
        return unless field

        return field if field.is_a?(Date) || field.is_a?(Time) || field.is_a?(DateTime)

        field.value if field.respond_to?(:value)
      end

      def locked_entry?(path)
        Mayhem::FrontMatter::Document.locked?(path)
      end

      def fetch_event_body(url, stats)
        return unless url

        @content_fetcher.fetch(url)
      rescue Mayhem::Support::HttpClient::NotFoundError => e
        record_stat(:fetch_failed, stats)
        logger.warn "Source returned 404 for #{url}: #{e.message}"
        { html: '', canonical_url: url, not_found: true }
      rescue StandardError => e
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

      def org_dir
        @org_dir ||= begin
          repo = Mayhem::Models::Organization.repo
          repo.root.join(Mayhem::Models::Organization.collection_dir).to_s
        end
      end
    end

    class IcalImporterCLI
      include Mayhem::Loggable

      def self.run
        new.run
      end

      def initialize(
        http_client: nil
      )
        @http_client = http_client || Mayhem::Support::HttpClient.new
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
