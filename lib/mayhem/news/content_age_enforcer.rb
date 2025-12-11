# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'yaml'

require_relative '../logging'
require_relative '../content/content_pruner'
require_relative '../front_matter/document'

module Mayhem
  module News
    class ContentAgeEnforcer
      POSTS_DIR = '_posts'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      EVENTS_DIR = '_events'
      DEFAULT_MAX_AGE_DAYS = 365
      CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        posts_dir: POSTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        events_dir: EVENTS_DIR,
        config_path: CONFIG_PATH,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        clock: -> { Time.now },
        content_pruner: nil
      )
        @posts_dir = posts_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @events_dir = events_dir
        @config_path = config_path
        @logger = logger
        @clock = clock
        @content_pruner = content_pruner || Mayhem::Content::ContentPruner.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          images_dir: images_dir,
          assets_dir: assets_dir,
          logger: logger
        )
      end

      def run
        max_age_days = determine_max_age_days
        cutoff = @clock.call - (max_age_days * 24 * 60 * 60)
        posts = posts_older_than(cutoff)
        if posts.empty?
          @logger.info "No posts older than #{max_age_days} days were found."
          return
        end

        excluded_paths = posts.to_set { |entry| entry[:path] }

        # Collect event IDs from posts being removed
        removed_event_ids = posts.flat_map { |entry| entry[:events] }.uniq.compact

        posts.each do |entry|
          @logger.info "Removing post #{File.basename(entry[:path])}"
          remove_file(entry[:path])
        end

        removed_images = @content_pruner.cleanup_images(
          posts.flat_map { |entry| entry[:images] }.uniq,
          excluded_paths: excluded_paths
        )

        # Clean up events generated from removed posts
        cleanup_generated_events(removed_event_ids) if removed_event_ids.any?

        @logger.info "Removed #{posts.size} post#{'s' unless posts.size == 1} older than #{max_age_days} days."
        @logger.info "Removed #{removed_images.size} image metadata entr#{removed_images.size == 1 ? 'y' : 'ies'}."
      end

      private

      def determine_max_age_days
        value = read_config_value
        return value if value&.positive?

        DEFAULT_MAX_AGE_DAYS
      end

      def read_config_value
        return unless File.exist?(@config_path)

        config = YAML.safe_load_file(@config_path)
        number = config && config['content_max_age_days']
        Integer(number) if number
      rescue StandardError => e
        @logger.warn "Failed to read content_max_age_days from #{@config_path}: #{e.message}"
        nil
      end

      def posts_older_than(cutoff)
        Dir.glob(File.join(@posts_dir, '*.md')).each_with_object([]) do |path, memo|
          document = Mayhem::FrontMatter::Document.load(path, logger: @logger)
          next unless document

          published_at = parse_date(document.front_matter['date'])
          next unless published_at
          next unless published_at < cutoff

          memo << {
            path: path,
            images: @content_pruner.collect_image_ids(document.front_matter),
            events: collect_event_ids(document.front_matter)
          }
        end
      end

      def parse_date(value)
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time)

        Time.parse(value.to_s)
      rescue StandardError
        nil
      end

      def collect_event_ids(front_matter)
        Array(front_matter['events']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end

      def cleanup_generated_events(event_ids)
        removed = 0
        # Get all remaining posts and their event references
        remaining_event_refs = remaining_event_references

        event_ids.each do |event_id|
          event_path = File.join(@events_dir, "#{event_id}.md")
          next unless File.exist?(event_path)

          # Only remove events that were generated from posts
          document = Mayhem::FrontMatter::Document.load(event_path, logger: @logger)
          next unless document
          next unless document.front_matter['generated_from_post'] == true

          # Check if any remaining posts still reference this event
          if remaining_event_refs[event_id]&.positive?
            @logger.info "Keeping event #{event_id} (still referenced by #{remaining_event_refs[event_id]} post(s))"
            next
          end

          remove_file(event_path)
          removed += 1
          @logger.info "Removed generated event #{event_id}"
        end

        @logger.info "Removed #{removed} generated event#{'s' unless removed == 1}." if removed.positive?
      end

      def remaining_event_references
        counts = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          document = Mayhem::FrontMatter::Document.load(path, logger: @logger)
          next unless document

          events = document.front_matter['events']
          next unless events.is_a?(Array)

          events.each { |event_id| counts[event_id] += 1 }
        end
        counts
      end
    end
  end
end
