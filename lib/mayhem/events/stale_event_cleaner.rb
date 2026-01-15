# frozen_string_literal: true

require 'date'
require 'time'
require 'seldon'
require_relative '../models/event'

module Mayhem
  module Events
    class StaleEventCleaner
      include Seldon::Loggable

      GRACE_PERIOD_DAYS = 1

      class << self
        def cutoff_date(reference_time)
          reference_time.utc.to_date - GRACE_PERIOD_DAYS
        end

        def stale?(start_time:, end_time:, cutoff_date:)
          last_time = end_time || start_time
          last_time.utc.to_date < cutoff_date
        end
      end

      def initialize(
        clock: -> { Time.now }
      )
        @clock = clock
      end

      def run
        current_time = @clock.call
        cutoff_date = self.class.cutoff_date(current_time)
        removed = []

        stale_candidates = Mayhem::Models::Event.where(
          'start_date' => lambda { |value|
            !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
          }
        )

        stale_candidates.each do |event|
          start_time = parse_time(event.start_date, event.id, 'start_date', required: true)
          next unless start_time

          end_time = parse_time(event.end_date, event.id, 'end_date', required: false)
          next unless self.class.stale?(start_time: start_time, end_time: end_time, cutoff_date: cutoff_date)

          event_id = event.id
          remove_event_from_post(event)
          event.destroy
          removed << event_id
          logger.info "Removed past event #{event_id}"
        end

        if removed.empty?
          logger.info 'No past events were removed.'
        else
          logger.info "Removed #{removed.size} past event#{'s' unless removed.size == 1}."
        end
      end

      private

      def parse_time(value, event_id, field_name, required:)
        if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          logger.warn "Skipping #{event_id}: missing #{field_name}" if required
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
        logger.warn "Skipping #{event_id}: invalid #{field_name} '#{value}' (#{e.message})"
        nil
      end

      def remove_event_from_post(event)
        post = event.news
        return unless post

        event_ids = Array(post.event_ids)
        event_path = event.path.to_s
        event_identifiers = [event.id, event_path].map(&:to_s)
        updated_events = event_ids.reject do |existing_id|
          event_identifiers.include?(existing_id.to_s)
        end
        return unless updated_events.size < event_ids.size

        post['event_ids'] = updated_events
        post.save!
        logger.info "Cleaned event links from #{post.id}"
      end
    end
  end
end
