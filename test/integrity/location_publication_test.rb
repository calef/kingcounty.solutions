# frozen_string_literal: true

require 'yaml'
require_relative '../test_helper'

class LocationPublicationTest < Minitest::Test
  def setup
    @documents = load_documents('_events/*.md') + load_documents('_posts/*.md')
  end

  def test_empty_locations_lists_are_unpublished
    errors = []

    documents.each do |doc|
      front = doc[:data]
      next unless front.key?('locations')

      locations = front['locations']
      next unless locations.is_a?(Array) && locations.empty?

      published = front.fetch('published', nil)
      errors << "#{doc[:path]} must set published: false when locations is an empty list" unless published == false
    end

    assert_empty errors, "Empty location list publishing issues:\n#{errors.join("\n")}"
  end

  def test_documents_include_locations_attribute
    errors = []

    documents.each do |doc|
      errors << "#{doc[:path]} must include the locations front matter attribute" unless doc[:data].key?('locations')
    end

    assert_empty errors, "Missing locations attribute:\n#{errors.join("\n")}"
  end

  private

  attr_reader :documents

  def load_documents(glob)
    Dir[glob].map { |path| { path: path, data: read_front_matter(path) } }
  end

  def read_front_matter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---/m)
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
end
