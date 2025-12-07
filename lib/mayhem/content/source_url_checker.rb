# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require 'uri'

require_relative '../logging'
require_relative '../support/front_matter_document'

module Mayhem
  module Content
    class SourceUrlChecker
      POSTS_DIR = '_posts'
      EVENTS_DIR = '_events'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      MAX_REDIRECTS = 5

      def initialize(
        posts_dir: POSTS_DIR,
        events_dir: EVENTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        http_client: nil
      )
        @posts_dir = posts_dir
        @events_dir = events_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @logger = logger
        @http_client = http_client
      end

      def run
        check_posts
        check_events
      end

      private

      def check_posts
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = check_url(source_url)
          
          case status
          when :not_found
            @logger.info "Source URL not found for post #{File.basename(path)}: #{source_url}"
            unpublish_post(path, document)
          when :error
            @logger.warn "Error checking source URL for post #{File.basename(path)}: #{source_url}"
          end
        end
      end

      def check_events
        Dir.glob(File.join(@events_dir, '*.md')).each do |path|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          source_url = document.front_matter['source_url']
          next if source_url.nil? || source_url.empty?

          status = check_url(source_url)
          
          case status
          when :not_found
            @logger.info "Source URL not found for event #{File.basename(path)}: #{source_url}"
            delete_event(path, document)
          when :error
            @logger.warn "Error checking source URL for event #{File.basename(path)}: #{source_url}"
          end
        end
      end

      def check_url(url, redirect_count = 0)
        return :error if redirect_count >= MAX_REDIRECTS

        uri = URI.parse(url)
        return :error unless %w[http https].include?(uri.scheme)

        if @http_client
          return @http_client.call(url)
        end

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                     open_timeout: 10, read_timeout: 10) do |http|
          request = Net::HTTP::Head.new(uri.request_uri)
          request['User-Agent'] = 'King County Solutions Link Checker'
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          :success
        when Net::HTTPNotFound, Net::HTTPGone
          :not_found
        when Net::HTTPRedirection
          location = response['location']
          return :error unless location

          # Handle relative redirects
          redirect_uri = URI.parse(location)
          redirect_uri = uri + location if redirect_uri.relative?
          
          check_url(redirect_uri.to_s, redirect_count + 1)
        else
          :error
        end
      rescue StandardError => e
        @logger.debug "Exception checking URL #{url}: #{e.message}"
        :error
      end

      def unpublish_post(path, document)
        @logger.info "Unpublishing post #{File.basename(path)}"
        
        front_matter = document.front_matter
        
        # Set published: false
        front_matter['published'] = false
        
        # Collect image IDs for cleanup
        image_ids = collect_image_ids(front_matter)
        
        # Clear images array
        front_matter['images'] = []
        
        # Save the modified document
        document.front_matter = front_matter
        document.save
        
        # Clean up unreferenced images
        cleanup_images(image_ids, path) if image_ids.any?
      end

      def delete_event(path, document)
        event_id = File.basename(path, '.md')
        @logger.info "Deleting event #{event_id}"
        
        # Remove the event file
        remove_file(path)
        
        # Clean up event references from posts
        clean_post_event_links([event_id])
      end

      def collect_image_ids(front_matter)
        Array(front_matter['images']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def cleanup_images(image_ids, excluded_post_path)
        # Get remaining image references (excluding the current post)
        remaining_refs = remaining_image_counts(Set[excluded_post_path])
        
        image_ids.each do |id|
          next if remaining_refs[id]&.positive?

          @logger.info "Removing unreferenced image #{id}"
          remove_file(File.join(@images_dir, "#{id}.md"))
          Dir.glob(File.join(@assets_dir, "#{id}.*")).each { |asset| remove_file(asset) }
        end
      end

      def remaining_image_counts(excluded_paths)
        counts = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
        end
        counts
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end

      def clean_post_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        
        Dir.glob(File.join(@posts_dir, '*.md')).each do |post_path|
          document = Mayhem::Support::FrontMatterDocument.load(post_path, logger: @logger)
          next unless document

          front_matter = document.front_matter
          events = front_matter['events']
          next unless events.is_a?(Array)
          next if events.empty?

          original_size = events.size
          updated_events = events.reject { |event_id| removed_set.include?(event_id) }

          next unless updated_events.size < original_size

          front_matter['events'] = updated_events
          document.front_matter = front_matter
          document.save
          @logger.info "Cleaned event links from #{File.basename(post_path)}"
        end
      end
    end
  end
end
