# frozen_string_literal: true

require 'set'
require 'yaml'
require 'test_helper'

class PlacesFrontMatterTest < Minitest::Test
  ZIP_CODE_REGEX = /\A\d{5}(?:-\d{4})?\z/
  ALLOWED_TYPES = [
    'Census-Designated Place',
    'City',
    'Country',
    'County',
    'County Region',
    'State',
    'Town'
  ].freeze

  def setup
    @places = load_documents('_places/*.md')
    @place_title_map = load_title_map('_places/*.md')
  end

  def test_latitude_if_present_is_numeric
    errors = []

    places.each do |doc|
      latitude = doc[:data]['latitude']
      next if latitude.nil?

      errors << "#{doc[:path]} latitude '#{latitude}' must be numeric" unless latitude.is_a?(Numeric)
    end

    assert errors.empty?, "Latitude issues:\n#{errors.join("\n")}"
  end

  def test_longitude_if_present_is_numeric
    errors = []

    places.each do |doc|
      longitude = doc[:data]['longitude']
      next if longitude.nil?

      errors << "#{doc[:path]} longitude '#{longitude}' must be numeric" unless longitude.is_a?(Numeric)
    end

    assert errors.empty?, "Longitude issues:\n#{errors.join("\n")}"
  end

  def test_parent_place_if_present_matches_a_place
    errors = []

    places.each do |doc|
      parent_place = value_as_string(doc, 'parent_place')
      next if parent_place.nil? || parent_place.empty?

      matching_paths = place_title_map[parent_place]
      if matching_paths.nil? || matching_paths.empty?
        errors << "#{doc[:path]} parent_place '#{parent_place}' must match another place title"
        next
      end

      if matching_paths.all? { |path| path == doc[:path] }
        errors << "#{doc[:path]} parent_place '#{parent_place}' must reference a different place document"
      end
    end

    assert errors.empty?, "Parent place issues:\n#{errors.join("\n")}"
  end

  def test_title_is_present_unique_and_string
    errors = []
    seen = Hash.new { |hash, key| hash[key] = [] }

    places.each do |doc|
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

    assert errors.empty?, "Title issues:\n#{errors.join("\n")}"
  end

  def test_type_is_present_string_and_allowed
    errors = []

    places.each do |doc|
      type = value_as_string(doc, 'type')
      if type.nil? || type.empty?
        errors << "#{doc[:path]} missing required type"
        next
      end

      unless ALLOWED_TYPES.include?(type)
        errors << "#{doc[:path]} type '#{type}' must be one of: #{ALLOWED_TYPES.join(', ')}"
      end
    end

    assert errors.empty?, "Type issues:\n#{errors.join("\n")}"
  end

  def test_zip_codes_if_present_are_valid_and_unique
    errors = []

    places.each do |doc|
      zips = doc[:data]['zip_codes']
      next if zips.nil?

      unless zips.is_a?(Array)
        errors << "#{doc[:path]} zip_codes must be an array"
        next
      end

      seen = Set.new
      zips.each do |zip|
        unless zip.is_a?(String) && zip.match?(ZIP_CODE_REGEX)
          errors << "#{doc[:path]} zip code '#{zip}' must be a valid US postal code"
          next
        end

        normalized = zip.strip
        if seen.include?(normalized)
          errors << "#{doc[:path]} zip code '#{zip}' is duplicated"
        else
          seen << normalized
        end
      end
    end

    assert errors.empty?, "ZIP code issues:\n#{errors.join("\n")}"
  end

  def test_filename_matches_title_slug
    errors = []

    places.each do |doc|
      title = value_as_string(doc, 'title')
      next if title.nil? || title.empty?

      expected_slug = slugify(title)
      actual_slug = File.basename(doc[:path], '.md')
      next if expected_slug == actual_slug

      errors << "#{doc[:path]} filename '#{actual_slug}' should be '#{expected_slug}'"
    end

    assert errors.empty?, "Filename issues:\n#{errors.join("\n")}"
  end

  def test_topic_summary_generated_if_present_is_true
    errors = []

    places.each do |doc|
      next unless doc[:data].key?('topic_summary_generated')

      value = doc[:data]['topic_summary_generated']
      errors << "#{doc[:path]} topic_summary_generated must be true if present" unless value == true
    end

    assert errors.empty?, "Topic summary issues:\n#{errors.join("\n")}"
  end

  private

  attr_reader :places, :place_title_map

  def load_documents(glob)
    Dir[glob].sort.map { |path| { path: path, data: read_front_matter(path) } }
  end

  def load_title_map(glob)
    Dir[glob].each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, map|
      data = read_front_matter(path)
      next unless data

      title = data['title']
      map[title] << path if title.is_a?(String)
    end
  end

  def read_front_matter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---/m)
    return {} unless match

    YAML.safe_load(match[1], permitted_classes: [], aliases: true) || {}
  end

  def value_as_string(doc, field)
    value = doc[:data][field]
    return unless value.is_a?(String)

    value.strip
  end

  def slugify(value)
    value.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
  end
end
