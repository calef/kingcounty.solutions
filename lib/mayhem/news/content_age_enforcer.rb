# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'seldon'
require 'time'
require 'yaml'

require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../front_matter/document'
require_relative '../models/event'
require_relative '../models/news'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module News
    class ContentAgeEnforcer
      include Seldon::Loggable

      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      DEFAULT_MAX_AGE_DAYS = 365
      CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        assets_dir: IMAGE_ASSETS_DIR,
        config_path: CONFIG_PATH,
        clock: -> { Time.now },
        news_pruner: nil,
        images_pruner: nil
      )
        @posts_dir = Mayhem::Models::News.collection_dir
        @assets_dir = assets_dir
        @config_path = config_path
        @clock = clock
        @images_pruner = images_pruner ||
                         Mayhem::Images::Pruner.new(
                           assets_dir: assets_dir
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         images_pruner: @images_pruner
                       )
      end

      def run
        max_age_days = determine_max_age_days
        cutoff = @clock.call - (max_age_days * 24 * 60 * 60)
        posts = posts_older_than(cutoff)
        if posts.empty?
          logger.info "No posts older than #{max_age_days} days were found."
          return
        end

        excluded_paths = posts.to_set { |entry| entry[:path] }

        # Collect event IDs from posts being removed
        removed_event_ids = posts.flat_map { |entry| entry[:event_ids] }.uniq.compact

        posts.each do |entry|
          logger.info "Removing post #{File.basename(entry[:path])}"
          remove_file(entry[:path])
        end

        removed_image_checksums = @news_pruner.prune_images(
          posts.flat_map { |entry| entry[:image_checksums] }.uniq,
          excluded_paths: excluded_paths
        )

        # Clean up events generated from removed posts
        prune_generated_events(removed_event_ids) if removed_event_ids.any?

        logger.info "Removed #{posts.size} post#{'s' unless posts.size == 1} older than #{max_age_days} days."
        logger.info "Removed #{removed_image_checksums.size} image metadata entr#{removed_image_checksums.size == 1 ? 'y' : 'ies'}."
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
        logger.warn "Failed to read content_max_age_days from #{@config_path}: #{e.message}"
        nil
      end

      def posts_older_than(cutoff)
        Dir.glob(File.join(@posts_dir, '*.md')).each_with_object([]) do |path, memo|
          document = Mayhem::FrontMatter::Document.load(path)
          next unless document

          published_at = parse_date(document.front_matter['date'])
          next unless published_at
          next unless published_at < cutoff

          memo << {
            path: path,
            image_checksums: @images_pruner.collect_image_checksums(document.front_matter),
            event_ids: collect_event_ids(document.front_matter)
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
        Array(front_matter['event_ids']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end

      def prune_generated_events(event_ids)
        removed = 0
        # Get all remaining posts and their event references
        remaining_event_refs = remaining_event_references

        event_ids.each do |event_id|
          event_path = event_path_for(event_id)
          next unless File.exist?(event_path)

          # Only remove events that were generated from posts
          document = Mayhem::FrontMatter::Document.load(event_path)
          next unless document
          next unless document.front_matter['generated_from_post'] == true

          # Check if any remaining posts still reference this event
          if remaining_event_refs[event_id]&.positive?
            logger.info "Keeping event #{event_id} (still referenced by #{remaining_event_refs[event_id]} post(s))"
            next
          end

          remove_file(event_path)
          removed += 1
          logger.info "Removed generated event #{event_id}"
        end

        logger.info "Removed #{removed} generated event#{'s' unless removed == 1}." if removed.positive?
      end

      def remaining_event_references
        counts = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          document = Mayhem::FrontMatter::Document.load(path)
          next unless document

          event_ids = document.front_matter['event_ids']
          next unless event_ids.is_a?(Array)

          event_ids.each { |event_id| counts[event_id] += 1 }
        end
        counts
      end

      def events_dir
        Mayhem::Models::Event.collection_dir
      end

      def event_path_for(event_id)
        root = Pathname.new(events_dir).parent
        root.join(event_id.to_s).to_s
      end
    end
  end
end
