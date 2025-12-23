# frozen_string_literal: true

require 'yaml'
require_relative '../test_helper'

class LocationPublicationTest < Minitest::Test
  def setup
    @documents = load_documents('_events/*.md') + load_documents('_posts/*.md')
  end

  def test_empty_location_titles_lists_are_unpublished
    errors = []

    documents.each do |doc|
      front = doc[:data]
      next unless front.key?('location_titles')

      location_titles = front['location_titles']
      next unless location_titles.is_a?(Array) && location_titles.empty?

      published = front.fetch('published', nil)
      unless published == false
        errors << "#{doc[:path]} must set published: false when location_titles is an empty list"
      end
    end

    assert_empty errors, "Empty location_titles list publishing issues:\n#{errors.join("\n")}"
  end

  def test_documents_include_location_titles_attribute
    errors = []

    documents.each do |doc|
      unless doc[:data].key?('location_titles')
        errors << "#{doc[:path]} must include the location_titles front matter attribute"
      end
    end

    assert_empty errors, "Missing location_titles attribute:\n#{errors.join("\n")}"
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
