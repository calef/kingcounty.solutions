# frozen_string_literal: true

require_relative '../logging'
require_relative '../content/content_pruner'
require_relative '../front_matter/document'
require_relative '../support/http_status_resolver'

module Mayhem
  module Content
    class SourceUrlChecker
      POSTS_DIR = '_posts'
      EVENTS_DIR = '_events'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')

      def initialize(
        posts_dir: POSTS_DIR,
        events_dir: EVENTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        http_client: nil,
        http_status_resolver: nil,
        content_pruner: nil,
        user_agent: 'King County Solutions Link Checker',
        workers: ENV.fetch('SOURCE_URL_CHECKER_WORKERS', '6').to_i
      )
        @posts_dir = posts_dir
        @events_dir = events_dir
        @logger = logger
        @user_agent = user_agent
        @http_status_resolver = http_status_resolver || Mayhem::Support::HttpStatusResolver.new(
          logger: @logger,
          user_agent: @user_agent,
          http_client: http_client
        )
        @content_pruner = content_pruner || Mayhem::Content::ContentPruner.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          images_dir: images_dir,
          assets_dir: assets_dir,
          logger: logger
        )
        @workers = [workers, 1].max
        @content_pruner_mutex = Mutex.new
      end

      def run
        check_posts
        check_events
      end

      private

      def check_posts
        process_documents(Dir.glob(File.join(@posts_dir, '*.md'))) do |path, document|
          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            @logger.info "Source URL not found for post #{File.basename(path)}: #{source_url}"
            with_pruner { @content_pruner.unpublish_post(path, document) }
          when :error
            @logger.warn "Error checking source URL for post #{File.basename(path)}: #{source_url}"
          end
        end
      end

      def check_events
        process_documents(Dir.glob(File.join(@events_dir, '*.md'))) do |path, document|
          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = @http_status_resolver.call(source_url)

          case status
          when :not_found
            @logger.info "Source URL not found for event #{File.basename(path)}: #{source_url}"
            with_pruner { @content_pruner.delete_event(path) }
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
        @content_pruner_mutex.synchronize(&)
      end
    end
  end
end
