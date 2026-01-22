# frozen_string_literal: true

require 'seldon'
require 'time'
require 'yaml'

require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../models/event'
require_relative '../models/news'

module Mayhem
  module News
    class ContentAgeEnforcer
      include Seldon::Loggable

      DEFAULT_MAX_AGE_DAYS = 365
      CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        config_path: CONFIG_PATH,
        clock: -> { Time.now },
        news_pruner: nil,
        images_pruner: nil
      )
        @config_path = config_path
        @clock = clock
        @images_pruner = images_pruner || Mayhem::Images::Pruner.new
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         images_pruner: @images_pruner
                       )
      end

      def run
        max_age_days = determine_max_age_days
        cutoff = @clock.call - (max_age_days * 24 * 60 * 60)
        old_posts = posts_older_than(cutoff)
        if old_posts.empty?
          logger.info "No posts older than #{max_age_days} days were found."
          return
        end

        # Collect data before destroying posts
        removed_event_ids = old_posts.flat_map { |post| collect_event_ids(post) }.uniq.compact
        image_checksums = old_posts.flat_map { |post| @images_pruner.collect_image_checksums(post) }.uniq

        old_posts.each do |post|
          record_id = post.id || post.path || 'unknown-post'
          logger.info "Removing post #{record_id}"
          post.destroy
        end

        # Posts are already deleted, so no exclusions needed
        removed_image_checksums = @news_pruner.prune_images(
          image_checksums,
          excluded_posts: []
        )

        # Clean up events generated from removed posts
        prune_generated_events(removed_event_ids) if removed_event_ids.any?

        logger.info "Removed #{old_posts.size} post#{'s' unless old_posts.size == 1} older than #{max_age_days} days."
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
        Mayhem::Models::News.all.select do |post|
          published_at = parse_date(post.date)
          published_at && published_at < cutoff
        end
      end

      def parse_date(value)
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time)

        Time.parse(value.to_s)
      rescue StandardError
        nil
      end

      def collect_event_ids(post)
        post.event_ids.map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def prune_generated_events(event_ids)
        removed = 0
        # Get all remaining posts and their event references
        remaining_event_refs = remaining_event_references

        event_ids.each do |event_id|
          event = find_event_by_id(event_id)
          next unless event

          # Only remove events that were generated from posts
          next unless event.generated_from_post?

          # Check if any remaining posts still reference this event
          if remaining_event_refs[event_id]&.positive?
            logger.info "Keeping event #{event_id} (still referenced by #{remaining_event_refs[event_id]} post(s))"
            next
          end

          event.destroy
          removed += 1
          logger.info "Removed generated event #{event_id}"
        end

        logger.info "Removed #{removed} generated event#{'s' unless removed == 1}." if removed.positive?
      end

      def remaining_event_references
        counts = Hash.new(0)
        Mayhem::Models::News.all.each do |post|
          post.event_ids.each { |event_id| counts[event_id] += 1 }
        end
        counts
      end

      def find_event_by_id(event_id)
        Mayhem::Models::Event.find(event_id)
      rescue FMRepo::NotFound
        nil
      end
    end
  end
end
