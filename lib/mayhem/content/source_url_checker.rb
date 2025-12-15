# frozen_string_literal: true

require_relative '../logging'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../news/pruner'
require_relative '../front_matter/document'
require_relative '../support/http_status_resolver'
require_relative '../news/repository'
require_relative '../events/repository'

module Mayhem
  module Content
    class SourceUrlChecker
      IMAGE_ASSETS_DIR = File.join('assets', 'images')

      def initialize(
        news_dir: nil,
        events_dir: nil,
        images_dir: nil,
        assets_dir: IMAGE_ASSETS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        http_client: nil,
        http_status_resolver: nil,
        news_pruner: nil,
        events_pruner: nil,
        images_pruner: nil,
        user_agent: 'King County Solutions Link Checker',
        workers: ENV.fetch('SOURCE_URL_CHECKER_WORKERS', '6').to_i,
        news_repository: nil,
        events_repository: nil
      )
        @news_dir = news_dir
        @events_dir = events_dir
        @logger = logger
        @user_agent = user_agent
        @news_repository = news_repository || Mayhem::News::Repository.new(
          directory: @news_dir || Mayhem::News::Repository::DEFAULT_DIR,
          logger: @logger
        )
        @events_repository = events_repository || Mayhem::Events::Repository.new(
          directory: @events_dir || Mayhem::Events::Repository::DEFAULT_DIR,
          logger: @logger
        )
        @http_status_resolver = http_status_resolver || Mayhem::Support::HttpStatusResolver.new(
          logger: @logger,
          user_agent: @user_agent,
          http_client: http_client
        )
        @images_pruner = images_pruner ||
                         Mayhem::Images::Pruner.new(
                           news_dir: news_dir,
                           events_dir: events_dir,
                           images_dir: images_dir,
                           assets_dir: assets_dir,
                           logger: logger
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         news_dir: news_dir,
                         images_pruner: @images_pruner,
                         logger: logger
                       )
        @events_pruner = events_pruner ||
                         Mayhem::Events::Pruner.new(
                           news_dir: news_dir,
                           events_dir: events_dir,
                           images_pruner: @images_pruner,
                           logger: logger
                         )
        @workers = [workers, 1].max
        @pruner_mutex = Mutex.new
      end

      def run
        check_news
        check_events
      end

      private

      def check_news
        process_documents(@news_repository.all_file_paths) do |path, document|
          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            @logger.info "Source URL not found for news article #{File.basename(path)}: #{source_url}"
            with_pruner { @news_pruner.unpublish(path, document) }
          when :error
            @logger.warn "Error checking source URL for news article #{File.basename(path)}: #{source_url}"
          end
        end
      end

      def check_events
        process_documents(@events_repository.all_file_paths) do |path, document|
          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            @logger.info "Source URL not found for event #{File.basename(path)}: #{source_url}"
            with_pruner { @events_pruner.delete(path) }
          when :error
            @logger.warn "Error checking source URL for event #{File.basename(path)}: #{source_url}"
          end
        end
      end

      def process_documents(paths)
        queue = Queue.new
        paths.each { |path| queue << path }

        threads = Array.new([paths.size, @workers].min) do
          Thread.new do
            loop do
              path = queue.pop(true)
              document = Mayhem::FrontMatter::Document.load(path, logger: @logger)
              next unless document

              yield(path, document)
            rescue ThreadError
              break
            rescue StandardError => e
              @logger.debug "Error processing #{path}: #{e.class}: #{e.message}"
            end
          end
        end

        threads.each(&:join)
      end

      def with_pruner(&)
        @pruner_mutex.synchronize(&)
      end
    end
  end
end
