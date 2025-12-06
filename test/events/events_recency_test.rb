# frozen_string_literal: true

require 'time'
require 'yaml'
require_relative '../test_helper'

class EventsRecencyTest < Minitest::Test
  def setup
    @events = load_documents('_events/*.md')
  end

  def test_events_are_not_in_the_past
    today = Date.today
    errors = []

    events.each do |doc|
      start_time = parse_start_time(doc[:data]['start_date'], doc[:path], errors)
      next unless start_time
      next unless start_time.to_date < today

      errors << "#{doc[:path]} start_date #{start_time.utc.iso8601} is earlier than #{today}"
    end

    assert_empty errors, "Remove or update events scheduled before today:\n#{errors.join("\n")}"
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

  def parse_start_time(value, path, errors)
    if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      errors << "#{path} missing required start_date"
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
    errors << "#{path} has invalid start_date '#{value}'"
    nil
  end
end
