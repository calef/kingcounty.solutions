# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'time'

require_relative '../logging'
require_relative '../support/front_matter_document'

module Mayhem
  module Events
    class StaleEventCleaner
      EVENTS_DIR = '_events'
      POSTS_DIR = '_posts'

      def initialize(
        events_dir: EVENTS_DIR,
        posts_dir: POSTS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        clock: -> { Time.now }
      )
        @events_dir = events_dir
        @posts_dir = posts_dir
        @logger = logger
        @clock = clock
      end

      def run
        current_time = @clock.call
        removed = []

        Dir.glob(File.join(@events_dir, '*.md')).each do |path|
          event_time = event_time_for(path)
          next unless event_time
          next unless event_time < current_time

          event_id = File.basename(path, '.md')
          remove_file(path)
          removed << event_id
          @logger.info "Removed past event #{File.basename(path)}"
        end

        # Clean up event references from posts
        clean_post_event_links(removed) if removed.any?

        if removed.empty?
          @logger.info 'No past events were removed.'
        else
          @logger.info "Removed #{removed.size} past event#{'s' unless removed.size == 1}."
        end
      end

      private

      def event_time_for(path)
        document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
        return unless document

        parse_start_time(document.front_matter['start_date'], path)
      end

      def parse_start_time(value, path)
        if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          @logger.warn "Skipping #{File.basename(path)}: missing start_date"
          return nil
        end

        case value
        when Time
          value
        when DateTime, Date
          value.to_time
        else
          Time.iso8601(value.to_s)
        end
      rescue ArgumentError => e
        @logger.warn "Skipping #{File.basename(path)}: invalid start_date '#{value}' (#{e.message})"
        nil
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end

      def clean_post_event_links(removed_event_ids)
        removed_set = removed_event_ids.to_set
        posts_updated = 0

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
          posts_updated += 1
          @logger.info "Cleaned event links from #{File.basename(post_path)}"
        end

        @logger.info "Updated #{posts_updated} post#{'s' unless posts_updated == 1} to remove deleted event links." if posts_updated.positive?
      end
    end
  end
end
