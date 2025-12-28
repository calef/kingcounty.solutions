# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../images/pruner'
require_relative '../logging'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Events
    class Pruner
      include Mayhem::Loggable

      def initialize(posts_dir:, events_dir:, images_pruner:)
        @posts_dir = posts_dir
        @events_dir = events_dir
        @images_pruner = images_pruner
      end

      def unpublish(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_checksums = @images_pruner.collect_image_checksums(front_matter)
        front_matter['image_checksums'] = []

        document.front_matter = front_matter
        document.save

        @images_pruner.prune(image_checksums, excluded_paths: Set[path]) if image_checksums.any?
      end

      def delete(path, document = nil)
        event_id = File.basename(path)

        # If document is provided, collect and prune images
        if document
          image_checksums = @images_pruner.collect_image_checksums(document.front_matter)
          delete_file(path)
          @images_pruner.prune(image_checksums, excluded_paths: Set[path]) if image_checksums.any?
        else
          delete_file(path)
        end

        prune_event_links([event_id])
      end

      def prune_images(image_checksums, excluded_paths:)
        @images_pruner.prune(image_checksums, excluded_paths: excluded_paths)
      end

      def collect_image_checksums(front_matter)
        @images_pruner.collect_image_checksums(front_matter)
      end

      private

      def prune_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

        Dir.glob(File.join(@posts_dir, '*.md')).each do |post_path|
          document = Mayhem::FrontMatter::Document.load(post_path)
          next unless document

          front_matter = document.front_matter
          event_ids = front_matter['event_ids']
          next unless event_ids.is_a?(Array)
          next if event_ids.empty?

          original_size = event_ids.size
          updated_events = event_ids.reject { |event_id| removed_set.include?(event_id) }
          next unless updated_events.size < original_size

          front_matter['event_ids'] = updated_events
          document.front_matter = front_matter
          document.save
          posts_updated += 1
          @logger.info "Cleaned event links from #{File.basename(post_path)}"
        end

        @logger.info "Updated #{posts_updated} post#{'s' unless posts_updated == 1} to remove deleted event links." if posts_updated.positive?
      end

      def delete_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
