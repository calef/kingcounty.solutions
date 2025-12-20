# frozen_string_literal: true

require 'time'
require 'uri'
require 'yaml'
require_relative '../test_helper'
require 'mayhem/models/topic'

class NewsFrontMatterTest < Minitest::Test
  def setup
    @posts = load_documents('_posts/*.md')
    @organization_titles = load_titles('_organizations/*.md')
    @topic_titles = Mayhem::Models::Topic.all.map(&:title)
    @image_checksums = load_field_values('_images/*.md', 'checksum')
    @event_documents = load_event_documents('_events/*.md')
    @event_slugs = event_documents.keys.to_set
  end

  def test_title_is_required
    errors = []

    posts.each do |doc|
      title = string_value(doc, 'title')
      next if title && !title.empty?

      errors << "#{doc[:path]} missing required title"
    end

    assert_empty errors, "Title issues:\n#{errors.join("\n")}"
  end

  def test_date_is_timestamp
    errors = []

    posts.each do |doc|
      value = doc[:data]['date']
      unless value
        errors << "#{doc[:path]} missing required date"
        next
      end

      date_string = value.is_a?(String) ? value : value.to_s
      errors << "#{doc[:path]} date '#{date_string}' must be an ISO8601 timestamp" unless timestamp?(date_string)
    end

    assert_empty errors, "Date issues:\n#{errors.join("\n")}"
  end

  def test_source_matches_an_organization_title
    errors = []

    posts.each do |doc|
      source = string_value(doc, 'source')
      if source.nil? || source.empty?
        errors << "#{doc[:path]} missing required source"
        next
      end

      next if organization_titles.include?(source)

      errors << "#{doc[:path]} source '#{source}' is not a known organization title"
    end

    assert_empty errors, "Source issues:\n#{errors.join("\n")}"
  end

  def test_source_url_is_optional_but_valid_if_present
    errors = []

    posts.each do |doc|
      source_url = string_value(doc, 'source_url')
      next if source_url.nil? || source_url.empty?
      next if valid_url?(source_url)

      errors << "#{doc[:path]} source_url '#{source_url}' must be a valid URL"
    end

    assert_empty errors, "Source URL issues:\n#{errors.join("\n")}"
  end

  def test_feed_content_is_optional_string
    errors = []

    posts.each do |doc|
      next unless doc[:data].key?('feed_content')

      value = doc[:data]['feed_content']
      next if value.is_a?(String)

      errors << "#{doc[:path]} feed_content must be a string"
    end

    assert_empty errors, "Feed content issues:\n#{errors.join("\n")}"
  end

  def test_original_source_html_is_optional_string
    errors = []

    posts.each do |doc|
      next unless doc[:data].key?('original_source_html')

      value = doc[:data]['original_source_html']
      next if value.is_a?(String)

      errors << "#{doc[:path]} original_source_html must be a string"
    end

    assert_empty errors, "Original source HTML issues:\n#{errors.join("\n")}"
  end

  def test_topics_reference_known_topics
    errors = []

    posts.each do |doc|
      topics = doc[:data]['topics']
      unless topics.is_a?(Array)
        errors << "#{doc[:path]} topics must be a list (empty list allowed)"
        next
      end

      topics.each do |topic|
        unless topic.is_a?(String)
          errors << "#{doc[:path]} topics must be strings: #{topic.inspect}"
          next
        end
        next if topic_titles.include?(topic)

        errors << "#{doc[:path]} topic '#{topic}' is not defined in _topics"
      end
    end

    assert_empty errors, "Topic issues:\n#{errors.join("\n")}"
  end

  def test_images_reference_known_checksums
    errors = []

    posts.each do |doc|
      images = doc[:data]['images']
      unless images.is_a?(Array)
        errors << "#{doc[:path]} images must be a list (empty list allowed)"
        next
      end

      images.each do |checksum|
        unless checksum.is_a?(String)
          errors << "#{doc[:path]} has non-string image reference #{checksum.inspect}"
          next
        end

        next if image_checksums.include?(checksum)

        errors << "#{doc[:path]} references missing image checksum #{checksum}"
      end
    end

    assert_empty errors, "Image issues:\n#{errors.join("\n")}"
  end

  def test_events_reference_known_event_files
    errors = []

    posts.each do |doc|
      events = doc[:data]['events']
      next unless events

      unless events.is_a?(Array)
        errors << "#{doc[:path]} events must be a list (empty list allowed)"
        next
      end

      events.each do |event_id|
        unless event_id.is_a?(String)
          errors << "#{doc[:path]} has non-string event reference #{event_id.inspect}"
          next
        end

        next if event_slugs.include?(event_id)

        errors << "#{doc[:path]} references missing event #{event_id}"
      end
    end

    assert_empty errors, "Event reference issues:\n#{errors.join("\n")}"
  end

  def test_unpublished_posts_have_no_images
    errors = []

    posts.each do |doc|
      next unless doc[:data]['published'] == false

      images = doc[:data]['images']
      next if images.is_a?(Array) && images.empty?

      errors << "#{doc[:path]} must not reference images when published: false"
    end

    assert_empty errors, "Unpublished image issues:\n#{errors.join("\n")}"
  end

  def test_posts_without_topics_are_unpublished
    errors = []

    posts.each do |doc|
      topics = doc[:data]['topics']
      next unless topics.is_a?(Array) && topics.empty?

      errors << "#{doc[:path]} must set published: false when topics list is empty" unless doc[:data]['published'] == false
    end

    assert_empty errors, "Topic-only publish issues:\n#{errors.join("\n")}"
  end

  def test_summarized_is_always_true
    errors = []

    posts.each do |doc|
      value = doc[:data]['summarized']
      errors << "#{doc[:path]} summarized must be true" unless value == true
    end

    assert_empty errors, "Summarized flag issues:\n#{errors.join("\n")}"
  end

  def test_openai_model_if_present_is_string
    errors = []

    posts.each do |doc|
      next unless doc[:data].key?('openai_model')
      next if doc[:data]['openai_model'].is_a?(String)

      errors << "#{doc[:path]} openai_model must be a string"
    end

    assert_empty errors, "openai_model issues:\n#{errors.join("\n")}"
  end

  def test_published_if_present_is_false
    errors = []

    posts.each do |doc|
      next unless doc[:data].key?('published')

      errors << "#{doc[:path]} published must be false" unless doc[:data]['published'] == false
    end

    assert_empty errors, "Published flag issues:\n#{errors.join("\n")}"
  end

  def test_events_reference_published_events
    errors = []

    posts.each do |doc|
      events = doc[:data]['events']
      next unless events.is_a?(Array)

      events.each do |event_id|
        event_document = event_documents[event_id]
        unless event_document
          errors << "#{doc[:path]} references missing event #{event_id}"
          next
        end

        event_data = event_document[:data]
        next unless event_data['published'] == false

        errors << "#{doc[:path]} references unpublished event #{event_id} (#{event_document[:path]})"
      end
    end

    assert_empty errors, "Event publication issues:\n#{errors.join("\n")}"
  end

  private

  attr_reader :posts, :organization_titles, :topic_titles, :image_checksums, :event_slugs, :event_documents

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

  def load_titles(glob)
    Dir[glob].each_with_object(Set.new) do |path, titles|
      data = read_front_matter(path)
      title = data['title']
      titles << title.strip if title.is_a?(String)
    end
  end

  def load_field_values(glob, field)
    Dir[glob].each_with_object(Set.new) do |path, values|
      data = read_front_matter(path)
      value = data[field]
      next unless value.is_a?(String)

      values << value
    end
  end

  def load_event_documents(glob)
    Dir[glob].each_with_object({}) do |path, collection|
      slug = File.basename(path, '.md')
      normalized_path = normalize_event_path(path)
      collection[slug] = { path: normalized_path, data: read_front_matter(path) }
    end
  end

  def string_value(doc, field)
    value = doc[:data][field]
    return unless value.is_a?(String)

    value.strip
  end

  def timestamp?(value)
    Time.iso8601(value)
    true
  rescue ArgumentError
    false
  end

  def valid_url?(value)
    uri = URI.parse(value)
    uri.host && %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end

  def normalize_event_path(path)
    return path if path.start_with?('_events/')

    marker = '/_events/'
    index = path.index(marker)
    return path unless index

    "_events/#{path[(index + marker.length)..]}"
  end
end
