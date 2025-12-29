# frozen_string_literal: true

require_relative '../logging'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../models/event'
require_relative '../models/news'
require_relative '../support/http_status_resolver'

module Mayhem
  module Content
    class SourceUrlChecker
      EVENTS_DIR = '_events'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')

      def initialize(
        events_dir: EVENTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        http_client: nil,
        http_status_resolver: nil,
        news_pruner: nil,
        events_pruner: nil,
        images_pruner: nil,
        news_model: Mayhem::Models::News,
        events_model: Mayhem::Models::Event,
        user_agent: 'King County Solutions Link Checker',
        workers: ENV.fetch('SOURCE_URL_CHECKER_WORKERS', '6').to_i
      )
        @events_dir = events_dir
        @user_agent = user_agent
        @http_status_resolver = http_status_resolver || Mayhem::Support::HttpStatusResolver.new(
          user_agent: @user_agent,
          http_client: http_client
        )
        @images_pruner = images_pruner ||
                         Mayhem::Images::Pruner.new(
                           events_dir: events_dir,
                           images_dir: images_dir,
                           assets_dir: assets_dir
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         images_pruner: @images_pruner
                       )
        @events_pruner = events_pruner ||
                         Mayhem::Events::Pruner.new(
                           events_dir: events_dir,
                           images_pruner: @images_pruner
                         )
        @news_model = news_model
        @posts_dir = @news_model.collection_dir
        @events_model = events_model
        @workers = [workers, 1].max
        @pruner_mutex = Mutex.new
      end

      def run
        check_posts
        check_events
      end

      private

      def check_posts
        records = @news_model.relation.to_a
        process_records(records) do |record|
          source_url = record.source_url.to_s.strip
          next if source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            logger.info "Source URL not found for post #{record_label(record)}: #{source_url}"
            with_pruner { unpublish_post(record) }
          when :error
            logger.warn "Error checking source URL for post #{record_label(record)}: #{source_url}"
          end
        end
      end

      def check_events
        records = @events_model.relation.to_a
        process_records(records) do |record|
          source_url = record.source_url.to_s.strip
          next if source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            logger.info "Source URL not found for event #{record_label(record)}: #{source_url}"
            with_pruner { delete_event(record) }
          when :error
            logger.warn "Error checking source URL for event #{record_label(record)}: #{source_url}"
          end
        end
      end

      def process_records(records)
        records = records.to_a
        queue = Queue.new
        records.each { |record| queue << record }

        threads = Array.new([records.size, @workers].min) do
          Thread.new do
            loop do
              record = queue.pop(true)
              yield(record)
            rescue ThreadError
              break
            rescue StandardError => e
              logger.debug "Error processing #{record_label(record)}: #{e.class}: #{e.message}"
            end
          end
        end

        threads.each(&:join)
      end

      def unpublish_post(record)
        image_checksums = @news_pruner.collect_image_checksums('image_checksums' => record.image_checksums)
        record['published'] = false
        record['image_checksums'] = []
        record.save!

        return if image_checksums.empty?

        excluded_path = record_path(record, base_dir: @posts_dir)
        excluded_paths = excluded_path.to_s.empty? ? Set.new : Set[excluded_path]
        @news_pruner.prune_images(image_checksums, excluded_paths: excluded_paths)
      end

      def delete_event(record)
        path = record_path(record, base_dir: @events_dir)
        image_checksums = @events_pruner.collect_image_checksums('image_checksums' => record.image_checksums)
        @events_pruner.delete(path)

        return if image_checksums.empty?

        excluded_paths = path.to_s.empty? ? Set.new : Set[path]
        @events_pruner.prune_images(image_checksums, excluded_paths: excluded_paths)
      end

      def record_path(record, base_dir:)
        path = record.path.to_s if record.respond_to?(:path) && record.path
        path = record.id.to_s if path.to_s.empty? && record.respond_to?(:id)
        return '' if path.to_s.empty?

        root = base_dir ? File.expand_path('..', base_dir.to_s) : Dir.pwd
        File.absolute_path(path, root)
      end

      def record_label(record)
        record.id.to_s
      end

      def with_pruner(&)
        @pruner_mutex.synchronize(&)
      end
    end
  end
end
