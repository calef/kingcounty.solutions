# frozen_string_literal: true

require 'seldon'

require_relative '../events/pruner'
require_relative '../news/pruner'
require_relative '../images/pruner'
require_relative '../models/event'
require_relative '../models/news'
require_relative '../models/organization'

module Mayhem
  module Organizations
    class Pruner
      include Seldon::Loggable

      def self.prune(organization_title)
        # Create pruner instances
        images_pruner = Mayhem::Images::Pruner.new

        events_pruner = Mayhem::Events::Pruner.new(
          images_pruner: images_pruner
        )

        news_pruner = Mayhem::News::Pruner.new(
          images_pruner: images_pruner
        )

        pruner = new(
          events_pruner: events_pruner,
          news_pruner: news_pruner
        )

        pruner.prune_organization_content(organization_title)
      end

      def initialize(events_pruner:, news_pruner:)
        @events_pruner = events_pruner
        @news_pruner = news_pruner
      end

      def prune_organization_content(organization_title)
        logger.info "Pruning content for organization: #{organization_title}"

        # Find and prune all events for this organization
        events_deleted = prune_events(organization_title)

        # Find and prune all news posts for this organization
        posts_deleted = prune_news(organization_title)

        # Delete the organization file itself
        organization_deleted = delete?(organization_title)

        logger.info "Pruned #{events_deleted} event(s) and #{posts_deleted} post(s) for #{organization_title}"
        result = { events: events_deleted, posts: posts_deleted, organization: organization_deleted }
        logger.info "Deletion complete: #{result[:events]} event(s), #{result[:posts]} post(s), and organization file removed"
        result
      end

      private

      def prune_events(organization_title)
        deleted_count = 0
        Mayhem::Models::Event.relation.to_a.each do |event|
          next unless event.organization_title == organization_title

          logger.info "Deleting event: #{event.id}"
          @events_pruner.delete(event)
          deleted_count += 1
        end
        deleted_count
      end

      def prune_news(organization_title)
        deleted_count = 0
        Mayhem::Models::News.all.each do |post|
          next unless post.organization_title == organization_title

          record_id = post.id
          logger.info "Deleting post: #{record_id}"
          @news_pruner.delete(post)

          deleted_count += 1
        end
        deleted_count
      end

      def delete?(organization_title)
        Mayhem::Models::Organization.all.each do |org|
          next unless org.title == organization_title

          record_id = org.id
          logger.info "Deleting organization file: #{record_id}"
          org.destroy
          return true
        end
        false
      end
    end
  end
end
