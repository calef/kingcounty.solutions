# frozen_string_literal: true

require 'date'
require 'etc'
require_relative '../logging'
require_relative '../support/front_matter_document'
require_relative '../feed_discovery'

module Mayhem
  module Organizations
    class FeedUpdater
      ORG_DIR = '_organizations'

      def initialize(
        feed_finder:,
        org_dir: ORG_DIR,
        targets: [],
        limit: nil,
        dry_run: false,
        concurrency: Etc.nprocessors,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @feed_finder = feed_finder
        @org_dir = org_dir
        @targets = targets
        @limit = limit
        @dry_run = dry_run
        @concurrency = [1, (concurrency || Etc.nprocessors).to_i].max
        @logger = logger
        @used_feeds = { rss: Set.new, ical: Set.new }
        @used_mutex = Mutex.new
      end

      def run
        validate_org_dir!

        file_list = files
        populate_used_feeds(file_list)
        queue = build_file_queue(file_list)
        processed = 0
        processed_mutex = Mutex.new
        results_mutex = Mutex.new
        updated = []
        skipped = []

        thread_count = file_list.size.clamp(1, @concurrency)
        workers = Array.new(thread_count) do
          Thread.new do
            loop do
              break if limit_reached?(processed_mutex, processed)

              file_name = next_file(queue)
              break unless file_name
              break if limit_reached?(processed_mutex, processed)

              if process_organization(file_name, updated, skipped, results_mutex)
                processed_mutex.synchronize { processed += 1 }
              end
            end
          end
        end

        workers.each(&:join)

        {
          processed: processed,
          updated: updated,
          skipped: skipped
        }
      end

      private

      def validate_org_dir!
        raise "Organization directory not found: #{@org_dir}" unless Dir.exist?(@org_dir)
      end

      def files
        entries = Dir.children(@org_dir).select { |name| name.end_with?('.md') }
        return entries unless @targets&.any?

        entries.select do |name|
          slug = File.basename(name, '.md')
          @targets.include?(slug)
        end
      end

      # rubocop:disable Naming/PredicateMethod
      def process_organization(file_name, updated, skipped, mutex)
        result = handle_organization(file_name)
        return false unless result

        if result[:feed_result]
          url_label = result[:feed_result].rss_url || result[:feed_result].ical_url
          mutex.synchronize { updated << [file_name, url_label] }
        else
          mutex.synchronize { skipped << file_name }
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod

      def build_file_queue(file_list)
        queue = Queue.new
        file_list.each { |file_name| queue << file_name }
        queue
      end

      def next_file(queue)
        queue.pop(true)
      rescue ThreadError
        nil
      end

      def limit_reached?(mutex, processed)
        return false unless @limit

        mutex.synchronize { processed >= @limit }
      end

      def handle_organization(file_name)
        path = File.join(@org_dir, file_name)
        document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
        return nil unless document

        front_matter = document.front_matter
        missing = missing_feed_fields(front_matter)
        return nil if missing.empty?

        website = valid_website(front_matter)
        return nil unless website

        @logger.info "Processing #{file_name} -> #{website}"
        feed_result = @feed_finder.find(website)
        unique_result = filter_unique_feed_result(feed_result, file_name)
        return record_success(document, unique_result) if unique_result&.any?

        record_failure(file_name, website)
      end

      def valid_website(front_matter)
        site = front_matter['website'].to_s.strip
        site.empty? ? nil : site
      end

      def missing_feed_fields(front_matter)
        [].tap do |missing|
          missing << :rss unless present_url?(front_matter['news_rss_url'])
          missing << :ical unless present_url?(front_matter['events_ical_url'])
        end
      end

      def present_url?(value)
        value && !value.to_s.strip.empty?
      end

      def populate_used_feeds(file_names)
        file_names.each do |file_name|
          path = File.join(@org_dir, file_name)
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          register_existing_feed(:rss, document.front_matter['news_rss_url'])
          register_existing_feed(:ical, document.front_matter['events_ical_url'])
        end
      end

      def register_existing_feed(type, url)
        normalized = normalize_feed_url(url)
        return unless normalized

        @used_mutex.synchronize { @used_feeds[type] << normalized }
      end

      def filter_unique_feed_result(feed_result, file_name)
        return nil unless feed_result

        filtered = Mayhem::FeedDiscovery::FeedResult.new
        if feed_result.rss_url && reserve_feed(:rss, feed_result.rss_url, file_name)
          filtered.rss_url = feed_result.rss_url
        end
        if feed_result.ical_url && reserve_feed(:ical, feed_result.ical_url, file_name)
          filtered.ical_url = feed_result.ical_url
        end
        filtered.any? ? filtered : nil
      end

      def reserve_feed(type, url, file_name)
        normalized = normalize_feed_url(url)
        return false unless normalized

        @used_mutex.synchronize do
          if @used_feeds[type].include?(normalized)
            @logger.info "#{feed_key(type)} already claimed; skipping #{file_name}"
            return false
          end
          @used_feeds[type] << normalized
          true
        end
      end

      def normalize_feed_url(url)
        return nil unless url

        canonical = url.to_s.strip
        return nil if canonical.empty?

        URI.parse(canonical).then do |uri|
          uri.fragment = nil
          uri.to_s
        end
      rescue URI::InvalidURIError
        canonical
      end

      def feed_key(type)
        type == :rss ? 'news_rss_url' : 'events_ical_url'
      end

      def record_success(document, feed_result)
        unless @dry_run
          document.front_matter['news_rss_url'] ||= feed_result.rss_url if feed_result.rss_url
          document.front_matter['events_ical_url'] ||= feed_result.ical_url if feed_result.ical_url
          document.save
        end
        details = []
        details << "news_rss_url=#{feed_result.rss_url}" if feed_result.rss_url
        details << "events_ical_url=#{feed_result.ical_url}" if feed_result.ical_url
        @logger.info "Found #{details.join(' and ')} for #{File.basename(document.path)}"
        { feed_result: feed_result }
      end

      def record_failure(file_name, website)
        @logger.info "No feed found for #{file_name} (#{website})"
        { feed_result: nil }
      end
    end

    class FeedUpdaterCLI
      def self.run
        new.run
      end

      def initialize(
        http_client: Mayhem::Support::HttpClient.new,
        feed_finder: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @logger = logger
        @http_client = http_client
        @feed_finder = feed_finder ||
                       Mayhem::FeedDiscovery::FeedFinder.new(@http_client, logger: @logger)
      end

      def run
        updater = FeedUpdater.new(
          org_dir: Mayhem::Organizations::FeedUpdater::ORG_DIR,
          targets: target_list,
          limit: limit_value,
          dry_run: ENV['DRY_RUN'] == '1',
          feed_finder: @feed_finder,
          concurrency: concurrency_value,
          logger: @logger
        )
        results = nil
        begin
          results = updater.run
          print_summary(results)
        rescue Interrupt
          @logger.info 'Interrupted; exiting update run'
          print_summary(results) if results
        end
      end

      private

      def target_list
        raw = ENV.fetch('TARGETS', '').strip
        return [] if raw.empty?

        raw.split(',').map(&:strip).reject(&:empty?)
      end

      def limit_value
        raw = ENV.fetch('LIMIT', '').strip
        return nil if raw.empty?

        raw.to_i
      end

      def concurrency_value
        raw = ENV.fetch('CONCURRENCY', '').strip
        return nil if raw.empty?

        raw.to_i
      end

      def print_summary(results)
        @logger.info(
          "Summary: processed=#{results[:processed]} found=#{results[:updated].length} " \
          "none=#{results[:skipped].length}"
        )
        results[:updated].each { |name, url| @logger.info "Updated #{name}: #{url}" }
      end
    end
  end
end
