# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'time'

require_relative '../logging'
require_relative '../front_matter/document'
require_relative 'repository'
require_relative '../news/repository'

module Mayhem
  module Events
    class StaleEventCleaner
      def initialize(
        events_dir: nil,
        posts_dir: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        clock: -> { Time.now },
        events_repository: nil,
        posts_repository: nil
      )
        @events_dir = events_dir
        @posts_dir = posts_dir
        @logger = logger
        @clock = clock
        @events_repository = events_repository || Mayhem::Events::Repository.new(
          directory: @events_dir || Mayhem::Events::Repository::DEFAULT_DIR,
          logger: @logger
        )
        @posts_repository = posts_repository || Mayhem::News::Repository.new(
          directory: @posts_dir || Mayhem::News::Repository::DEFAULT_DIR,
          logger: @logger
        )
      end

      def run
        current_time = @clock.call
        removed = []

        @events_repository.each do |document, path|
          event_time = event_time_for(document)
          next unless event_time
          next unless event_time < current_time

          event_id = @events_repository.identifier_from_path(path)
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

      def event_time_for(document)
        return unless document

        parse_start_time(document.front_matter['start_date'], document.path)
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

        @posts_repository.each do |document, post_path|
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
