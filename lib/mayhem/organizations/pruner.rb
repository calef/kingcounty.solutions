# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../events/pruner'
require_relative '../news/pruner'
require_relative '../images/pruner'

module Mayhem
  module Organizations
    class Pruner
      def self.prune(organization_title, logger:)
        # Set up directory paths
        posts_dir = File.expand_path('_posts', Dir.pwd)
        events_dir = File.expand_path('_events', Dir.pwd)
        images_dir = File.expand_path('_images', Dir.pwd)
        assets_dir = File.expand_path('assets/images', Dir.pwd)

        # Create pruner instances
        images_pruner = Mayhem::Images::Pruner.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          images_dir: images_dir,
          assets_dir: assets_dir,
          logger: logger
        )

        events_pruner = Mayhem::Events::Pruner.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          images_pruner: images_pruner,
          logger: logger
        )

        news_pruner = Mayhem::News::Pruner.new(
          posts_dir: posts_dir,
          images_pruner: images_pruner,
          logger: logger
        )

        pruner = new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          events_pruner: events_pruner,
          news_pruner: news_pruner,
          logger: logger
        )

        pruner.prune_organization_content(organization_title)
      end

      def initialize(posts_dir:, events_dir:, events_pruner:, news_pruner:, logger:)
        @posts_dir = posts_dir
        @events_dir = events_dir
        @events_pruner = events_pruner
        @news_pruner = news_pruner
        @logger = logger
      end

      def prune_organization_content(organization_title)
        @logger.info "Pruning content for organization: #{organization_title}"

        # Find and prune all events for this organization
        events_deleted = prune_events(organization_title)

        # Find and prune all news posts for this organization
        posts_deleted = prune_news(organization_title)

        @logger.info "Pruned #{events_deleted} event(s) and #{posts_deleted} post(s) for #{organization_title}"
        result = { events: events_deleted, posts: posts_deleted }
        @logger.info "Deletion complete: #{result[:events]} event(s) and #{result[:posts]} post(s) removed"
        result
      end

      private

      def prune_events(organization_title)
        deleted_count = 0
        Dir.glob(File.join(@events_dir, '*.md')).each do |event_path|
          document = Mayhem::FrontMatter::Document.load(event_path, logger: @logger)
          next unless document

          source = document.front_matter['source']
          next unless source == organization_title

          @logger.info "Deleting event: #{File.basename(event_path)}"
          @events_pruner.delete(event_path, document)
          deleted_count += 1
        end
        deleted_count
      end

      def prune_news(organization_title)
        deleted_count = 0
        Dir.glob(File.join(@posts_dir, '*.md')).each do |post_path|
          document = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)
          next unless document

          source = document.front_matter['source']
          next unless source == organization_title

          @logger.info "Deleting post: #{File.basename(post_path)}"
          @news_pruner.delete(post_path, document)

          deleted_count += 1
        end
        deleted_count
      end
    end
  end
end
