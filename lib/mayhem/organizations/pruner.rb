# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../events/pruner'
require_relative '../news/pruner'
require_relative '../images/pruner'
require_relative '../models/news'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Organizations
    class Pruner
      def self.prune(organization_title, logger:)
        # Set up directory paths
        events_dir = File.expand_path('_events', Dir.pwd)
        images_dir = File.expand_path('_images', Dir.pwd)
        assets_dir = File.expand_path('assets/images', Dir.pwd)
        organizations_dir = File.expand_path('_organizations', Dir.pwd)

        # Create pruner instances
        images_pruner = Mayhem::Images::Pruner.new(
          events_dir: events_dir,
          images_dir: images_dir,
          assets_dir: assets_dir,
          logger: logger
        )

        events_pruner = Mayhem::Events::Pruner.new(
          events_dir: events_dir,
          images_pruner: images_pruner,
          logger: logger
        )

        news_pruner = Mayhem::News::Pruner.new(
          images_pruner: images_pruner,
          logger: logger
        )

        pruner = new(
          events_dir: events_dir,
          organizations_dir: organizations_dir,
          events_pruner: events_pruner,
          news_pruner: news_pruner,
          logger: logger
        )

        pruner.prune_organization_content(organization_title)
      end

      def initialize(events_dir:, organizations_dir:, events_pruner:, news_pruner:, logger:)
        @posts_dir = Mayhem::Models::News.collection_dir
        @events_dir = events_dir
        @organizations_dir = organizations_dir
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

        # Delete the organization file itself
        organization_deleted = delete?(organization_title)

        @logger.info "Pruned #{events_deleted} event(s) and #{posts_deleted} post(s) for #{organization_title}"
        result = { events: events_deleted, posts: posts_deleted, organization: organization_deleted }
        @logger.info "Deletion complete: #{result[:events]} event(s), #{result[:posts]} post(s), and organization file removed"
        result
      end

      private

      def prune_events(organization_title)
        deleted_count = 0
        Dir.glob(File.join(@events_dir, '*.md')).each do |event_path|
          document = Mayhem::FrontMatter::Document.load(event_path, logger: @logger)
          next unless document

          event_org = document.front_matter['organization_title']
          next unless event_org == organization_title

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

          source = document.front_matter['organization_title']
          next unless source == organization_title

          @logger.info "Deleting post: #{File.basename(post_path)}"
          @news_pruner.delete(post_path, document)

          deleted_count += 1
        end
        deleted_count
      end

      def delete?(organization_title)
        Dir.glob(File.join(@organizations_dir, '*.md')).each do |org_path|
          document = Mayhem::FrontMatter::Document.load(org_path, logger: @logger)
          next unless document

          title = document.front_matter['title']
          next unless title == organization_title

          @logger.info "Deleting organization file: #{File.basename(org_path)}"
          delete_file(org_path)
          return true
        end
        false
      end

      def delete_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
