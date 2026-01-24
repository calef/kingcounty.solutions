# frozen_string_literal: true

require 'seldon'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../models/event'
require_relative '../models/news'
require_relative '../threading/pool_executor'

module Mayhem
  module Content
    class SourceUrlChecker
      include Seldon::Loggable

      def initialize(
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
        @images_pruner = images_pruner || Mayhem::Images::Pruner.new
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
        @executor = Threading::PoolExecutor.new(workers: @workers)
      end

      def run
        check_posts
        check_events
      end

      private

      def check_posts
        records = @news_model.relation.to_a
        @executor.run(records, on_error: method(:log_processing_error)) do |record|
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
        @executor.run(records, on_error: method(:log_processing_error)) do |record|
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

      def log_processing_error(record, error)
        logger.debug "Error processing #{record_label(record)}: #{error.class}: #{error.message}"
      end

      def unpublish_post(record)
        @news_pruner.unpublish(record)
      end

      def delete_event(record)
        @events_pruner.delete(record)
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
