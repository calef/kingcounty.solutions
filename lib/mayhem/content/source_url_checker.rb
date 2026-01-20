# frozen_string_literal: true

require 'seldon'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../models/event'
require_relative '../models/news'

module Mayhem
  module Content
    class SourceUrlChecker
      include Seldon::Loggable

      IMAGE_ASSETS_DIR = File.join('assets', 'images')

      def initialize(
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
        @user_agent = user_agent
        @http_status_resolver = http_status_resolver || Seldon::Support::HttpStatusResolver.new(
          user_agent: @user_agent,
          http_client: http_client
        )
        @images_pruner = images_pruner ||
                         Mayhem::Images::Pruner.new(
                           assets_dir: assets_dir
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         images_pruner: @images_pruner
                       )
        @events_pruner = events_pruner ||
                         Mayhem::Events::Pruner.new(
                           images_pruner: @images_pruner
                         )
        @news_model = news_model
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
        image_checksums = @images_pruner.collect_image_checksums('image_checksums' => record.image_checksums)
        record['published'] = false
        record['image_checksums'] = []
        record.save!

        return if image_checksums.empty?

        @news_pruner.prune_images(image_checksums, excluded_posts: [record])
      end

      def delete_event(record)
        image_checksums = @images_pruner.collect_image_checksums('image_checksums' => record.image_checksums)
        @events_pruner.delete(record)

        return if image_checksums.empty?

        @events_pruner.prune_images(image_checksums, excluded_events: [record])
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
