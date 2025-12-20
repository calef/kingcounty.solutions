# frozen_string_literal: true

require 'time'
require 'yaml'
require_relative '../test_helper'
require 'mayhem/events/stale_event_cleaner'

class EventsRecencyTest < Minitest::Test
  def setup
    @events = load_documents('_events/*.md')
  end

  def test_events_are_not_in_the_past
    cutoff_date = Mayhem::Events::StaleEventCleaner.cutoff_date(Time.now)
    errors = []

    events.each do |doc|
      start_time = parse_time(doc[:data]['start_date'], doc[:path], 'start_date', errors, required: true)
      next unless start_time
      end_time = parse_time(doc[:data]['end_date'], doc[:path], 'end_date', errors, required: false)
      next unless Mayhem::Events::StaleEventCleaner.stale?(
        start_time: start_time,
        end_time: end_time,
        cutoff_date: cutoff_date
      )

      window_end = (end_time || start_time).utc.iso8601
      errors << "#{doc[:path]} ends at #{window_end} which is earlier than #{cutoff_date}"
    end

    assert_empty errors, "Remove or update events scheduled before yesterday:\n#{errors.join("\n")}"
  end

  private

  attr_reader :events

  def load_documents(glob)
    Dir[glob].map do |path|
      { path: path, data: read_front_matter(path) }
    end
  end

  def read_front_matter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*/m)
    return {} unless match

    YAML.safe_load(
      match[1],
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    ) || {}
  rescue Psych::SyntaxError => e
    raise "Failed to parse #{path}: #{e.message}"
  end

  def parse_time(value, path, field_name, errors, required:)
    if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      errors << "#{path} missing required #{field_name}" if required
      return nil
    end

    timestamp =
      case value
      when Time
        value
      when DateTime
        value.to_time
      when Date
        value.to_time
      else
        Time.iso8601(value.to_s)
      end

    timestamp
  rescue ArgumentError
    errors << "#{path} has invalid #{field_name} '#{value}'"
    nil
  end
end
