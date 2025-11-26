# frozen_string_literal: true

require 'date'
require_relative '../logging'
require_relative '../support/front_matter_document'
require_relative '../news/feed_discovery'

module Mayhem
  module Organizations
    # Discovers RSS/Atom feeds for organizations and stores them in front matter.
    class FeedUpdater
      ORG_DIR = '_organizations'

      def initialize(
        feed_finder:,
        org_dir: ORG_DIR,
        targets: [],
        limit: nil,
        dry_run: false,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @feed_finder = feed_finder
        @org_dir = org_dir
        @targets = targets
        @limit = limit
        @dry_run = dry_run
        @logger = logger
      end

      def run
        validate_org_dir!

        processed = 0
        updated = []
        skipped = []
        files.each do |file_name|
          break if @limit && processed >= @limit

          processed += 1 if process_organization?(file_name, updated, skipped)
        end

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

      def process_organization?(file_name, updated, skipped)
        result = handle_organization(file_name)
        return false unless result

        bucket = result[:feed_url] ? updated : skipped
        bucket << (result[:feed_url] ? [file_name, result[:feed_url]] : file_name)
        true
      end

      def handle_organization(file_name)
        path = File.join(@org_dir, file_name)
        document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
        return nil unless document

        front_matter = document.front_matter
        website = valid_website(front_matter)
        return nil unless website

        @logger.info "Processing #{file_name} -> #{website}"
        feed_url = @feed_finder.find(website)
        return record_success(document, feed_url) if feed_url

        record_failure(file_name, website)
      end

      def valid_website(front_matter)
        site = front_matter['website'].to_s.strip
        return nil if site.empty? || front_matter['news_rss_url']

        site
      end

      def record_success(document, feed_url)
        unless @dry_run
          document.front_matter['news_rss_url'] = feed_url
          document.save
        end
        @logger.info "Found feed for #{File.basename(document.path)}: #{feed_url}"
        { feed_url: feed_url }
      end

      def record_failure(file_name, website)
        @logger.info "No feed found for #{file_name} (#{website})"
        { feed_url: nil }
      end
    end

    # CLI wrapper around FeedUpdater that wires defaults and env flags.
    class FeedUpdaterCLI
      def self.run
        new.run
      end

      def initialize(
        http_client: Mayhem::News::FeedDiscovery::HttpClient.new,
        feed_finder: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @logger = logger
        @http_client = http_client
        @feed_finder = feed_finder ||
                       Mayhem::News::FeedDiscovery::FeedFinder.new(@http_client, logger: @logger)
      end

      def run
        updater = FeedUpdater.new(
          org_dir: Mayhem::Organizations::FeedUpdater::ORG_DIR,
          targets: target_list,
          limit: limit_value,
          dry_run: ENV['DRY_RUN'] == '1',
          feed_finder: @feed_finder,
          logger: @logger
        )
        results = updater.run
        print_summary(results)
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

      def print_summary(results)
        @logger.info "Summary: processed=#{results[:processed]} " \
                     "found=#{results[:updated].length} " \
                     "none=#{results[:skipped].length}"
        results[:updated].each do |name, url|
          @logger.info "Updated #{name}: #{url}"
        end
      end
    end
  end
end
