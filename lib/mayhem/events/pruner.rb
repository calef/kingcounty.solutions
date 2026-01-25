# frozen_string_literal: true

require_relative '../pruners/base'
require_relative '../models/news'

module Mayhem
  module Events
    class Pruner < Mayhem::Pruners::Base
      private

      def exclusion_key
        :excluded_event_ids
      end

      def after_delete(record_id)
        prune_event_links([record_id])
      end

      def prune_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

        Mayhem::Models::News.relation.to_a.each do |post|
          event_ids = post.event_ids
          next if event_ids.empty?

          original_size = event_ids.size
          updated_events = event_ids.reject { |event_id| removed_set.include?(event_id) }
          next unless updated_events.size < original_size

          post.event_ids = updated_events
          post.save!
          posts_updated += 1
          logger.info "Cleaned event links from #{post.id}"
        end

        return unless posts_updated.positive?

        logger.info "Updated #{posts_updated} post#{'s' unless posts_updated == 1} to remove deleted event links."
      end
    end
  end
end
