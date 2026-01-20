# frozen_string_literal: true

require_relative '../images/pruner'
require 'seldon'
require_relative '../models/event'
require_relative '../models/news'

module Mayhem
  module Events
    class Pruner
      include Seldon::Loggable

      def initialize(images_pruner:)
        @images_pruner = images_pruner
      end

      def unpublish(document)
        document['published'] = false
        image_checksums = @images_pruner.collect_image_checksums(document)
        document['image_checksums'] = []
        document.save!

        @images_pruner.prune(image_checksums, excluded_events: [document]) if image_checksums.any?
      end

      def delete(event)
        return unless event

        image_checksums = @images_pruner.collect_image_checksums(event)
        event_id = event.id.to_s
        event&.destroy

        @images_pruner.prune(image_checksums, excluded_events: [event]) if image_checksums.any?
        prune_event_links([event_id])
      end

      def prune_images(image_checksums, excluded_events:)
        @images_pruner.prune(image_checksums, excluded_events: excluded_events)
      end

      private

      def prune_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

        Mayhem::Models::News.relation.to_a.each do |post|
          event_ids = post['event_ids']
          next unless event_ids.is_a?(Array)
          next if event_ids.empty?

          original_size = event_ids.size
          updated_events = event_ids.reject { |event_id| removed_set.include?(event_id) }
          next unless updated_events.size < original_size

          post['event_ids'] = updated_events
          post.save!
          posts_updated += 1
          logger.info "Cleaned event links from #{post.id}"
        end

        logger.info "Updated #{posts_updated} post#{'s' unless posts_updated == 1} to remove deleted event links." if posts_updated.positive?
      end
    end
  end
end
