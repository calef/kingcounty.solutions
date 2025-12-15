# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../images/pruner'
require_relative '../news/repository'

module Mayhem
  module Events
    class Pruner
      def initialize(images_pruner:, logger:, posts_dir: nil, events_dir: nil, posts_repository: nil, events_repository: nil)
        @posts_dir = posts_dir
        @events_dir = events_dir
        @images_pruner = images_pruner
        @logger = logger
        @posts_repository = posts_repository || Mayhem::News::Repository.new(
          directory: @posts_dir || Mayhem::News::Repository::DEFAULT_DIR,
          logger: @logger
        )
        @events_repository = events_repository || (events_dir ? Mayhem::Events::Repository.new(directory: events_dir, logger: @logger) : nil)
      end

      def unpublish(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_ids = @images_pruner.collect_image_ids(front_matter)
        front_matter['images'] = []

        document.front_matter = front_matter
        document.save

        @images_pruner.prune(image_ids, excluded_paths: Set[path]) if image_ids.any?
      end

      def delete(path)
        event_id = if @events_repository
                     @events_repository.identifier_from_path(path)
                   else
                     File.basename(path, '.md')
                   end
        delete_file(path)
        prune_event_links([event_id])
      end

      def prune_images(image_ids, excluded_paths:)
        @images_pruner.prune(image_ids, excluded_paths: excluded_paths)
      end

      def collect_image_ids(front_matter)
        @images_pruner.collect_image_ids(front_matter)
      end

      private

      def prune_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

        @posts_repository.each do |document, post_path|
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

      def delete_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
