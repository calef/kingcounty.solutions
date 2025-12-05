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

      def initialize(
        events_dir: EVENTS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        clock: -> { Time.now }
      )
        @events_dir = events_dir
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

          remove_file(path)
          removed << path
          @logger.info "Removed past event #{File.basename(path)}"
        end

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
    end
  end
end
