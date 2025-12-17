# frozen_string_literal: true

require_relative '../test_helper'
require 'mayhem/models/location'

class LocationsFrontMatterTest < Minitest::Test
  ALLOWED_TYPES = [
    'Census-Designated Place',
    'City',
    'County',
    'County Region',
    'Town'
  ].freeze

  def setup
    @locations = load_documents
    @location_title_map = load_title_map(@locations)
  end

  def test_parent_location_if_present_matches_a_place
    errors = []

    locations.each do |doc|
      parent_location = value_as_string(doc, 'parent_location')
      next if parent_location.nil? || parent_location.empty?

      matching_paths = location_title_map[parent_location]
      if matching_paths.nil? || matching_paths.empty?
        errors << "#{doc[:path]} parent_location '#{parent_location}' must match another place title"
        next
      end

      if matching_paths.all? { |path| path == doc[:path] }
        errors << "#{doc[:path]} parent_location '#{parent_location}' must reference a different place document"
      end
    end

    assert_empty errors, "Parent location issues:\n#{errors.join("\n")}"
  end

  def test_title_is_present_unique_and_string
    errors = []
    seen = Hash.new { |hash, key| hash[key] = [] }

    locations.each do |doc|
      title = value_as_string(doc, 'title')
      if title.nil? || title.empty?
        errors << "#{doc[:path]} missing required title"
        next
      end

      seen[title] << doc[:path]
    end

    seen.each do |title, paths|
      next if paths.one?

      errors << "title '#{title}' appears in #{paths.join(', ')}"
    end

    assert_empty errors, "Title issues:\n#{errors.join("\n")}"
  end

  def test_type_is_present_string_and_allowed
    errors = []

    locations.each do |doc|
      type = value_as_string(doc, 'type')
      if type.nil? || type.empty?
        errors << "#{doc[:path]} missing required type"
        next
      end

      unless ALLOWED_TYPES.include?(type)
        errors << "#{doc[:path]} type '#{type}' must be one of: #{ALLOWED_TYPES.join(', ')}"
      end
    end

    assert_empty errors, "Type issues:\n#{errors.join("\n")}"
  end

  def test_filename_matches_title_slug
    errors = []

    locations.each do |doc|
      title = value_as_string(doc, 'title')
      next if title.nil? || title.empty?

      expected_slug = slugify(title)
      actual_slug = File.basename(doc[:path], '.md')
      next if expected_slug == actual_slug

      errors << "#{doc[:path]} filename '#{actual_slug}' should be '#{expected_slug}'"
    end

    assert_empty errors, "Filename issues:\n#{errors.join("\n")}"
  end

  private

  attr_reader :locations, :location_title_map

  def load_documents
    Mayhem::Models::Location.all.to_a.map do |location|
      { path: location.id, data: location.front_matter }
    end
  end

  def load_title_map(locations)
    locations.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |doc, map|
      data = doc[:data]
      title = data['title']
      map[title] << doc[:path] if title.is_a?(String)
    end
  end

  def value_as_string(doc, field)
    value = doc[:data][field]
    return unless value.is_a?(String)

    value.strip
  end

  def slugify(title)
    title.downcase
         .gsub(/[^a-z0-9]+/, '-')
         .gsub(/\A-+|-+\z/, '')
  end
end
