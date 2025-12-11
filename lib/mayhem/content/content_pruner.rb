# frozen_string_literal: true

require 'fileutils'

require_relative 'image_cleanup'
require_relative '../front_matter/document'

module Mayhem
  module Content
    class ContentPruner
      attr_reader :posts_dir, :events_dir, :image_cleanup

      def initialize(
        posts_dir:,
        events_dir:,
        images_dir:,
        assets_dir:,
        logger:,
        image_cleanup: nil
      )
        @posts_dir = posts_dir
        @events_dir = events_dir
        @logger = logger
        @image_cleanup = image_cleanup || ImageCleanup.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          images_dir: images_dir,
          assets_dir: assets_dir,
          logger: logger
        )
      end

      def unpublish_post(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_ids = @image_cleanup.collect_image_ids(front_matter)
        front_matter['images'] = []

        document.front_matter = front_matter
        document.save

        @image_cleanup.cleanup(image_ids, excluded_paths: Set[path]) if image_ids.any?
      end

      def unpublish_event(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_ids = @image_cleanup.collect_image_ids(front_matter)
        front_matter['images'] = []

        document.front_matter = front_matter
        document.save

        # For events, we need to check both posts and events directories
        excluded_paths = Set[path]
        @image_cleanup.cleanup(image_ids, excluded_paths: excluded_paths) if image_ids.any?
      end

      def delete_event(path)
        event_id = File.basename(path, '.md')
        remove_file(path)
        clean_event_links([event_id])
      end

      def cleanup_images(image_ids, excluded_paths:)
        @image_cleanup.cleanup(image_ids, excluded_paths: excluded_paths)
      end

      def collect_image_ids(front_matter)
        @image_cleanup.collect_image_ids(front_matter)
      end

      private

      def clean_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

        Dir.glob(File.join(@posts_dir, '*.md')).each do |post_path|
          document = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)
          next unless document

          front_matter = document.front_matter
          events = front_matter['events']
          next unless events.is_a?(Array)
          next if events.empty?

          original_size = events.size
          updated_events = events.reject { |event_id| removed_set.include?(event_id) }
          next unless updated_events.size < original_size

          front_matter['events'] = updated_events
          document.front_matter = front_matter
          document.save
          posts_updated += 1
          @logger.info "Cleaned event links from #{File.basename(post_path)}"
        end

        @logger.info "Updated #{posts_updated} post#{'s' unless posts_updated == 1} to remove deleted event links." if posts_updated.positive?
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
