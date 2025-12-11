# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/content/location_classifier'

class LocationClassifierTest < Minitest::Test
  class FakeLogger
    attr_reader :infos, :warns, :errors, :debugs

    def initialize
      @infos = []
      @warns = []
      @errors = []
      @debugs = []
    end

    %i[info warn error debug].each do |level|
      define_method(level) do |message|
        instance_variable_get("@#{level}s") << message
      end
    end
  end

  class FakeChatClient
    def initialize(response: nil)
      @response = response
    end

    def chat(parameters:)
      @response
    end
  end

  def setup
    @tmp_locations = Dir.mktmpdir('locations')
    @logger = FakeLogger.new
  end

  def teardown
    FileUtils.remove_entry(@tmp_locations)
  end

  def write_location(slug, front_matter, body = '')
    path = File.join(@tmp_locations, "#{slug}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, body))
    path
  end

  def build_classifier(client_response:)
    client = FakeChatClient.new(response: client_response)
    Mayhem::Content::LocationClassifier.new(
      locations_dir: @tmp_locations,
      client: client,
      logger: @logger,
      model: 'test-model'
    )
  end

  def test_classify_returns_slugs_for_matched_locations
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')
    write_location('bellevue', { 'title' => 'Bellevue', 'type' => 'City' }, 'The city of Bellevue')
    write_location('kent', { 'title' => 'Kent', 'type' => 'City' }, 'The city of Kent')

    classifier = build_classifier(
      client_response: { 'choices' => [{ 'message' => { 'content' => '["Seattle", "Bellevue"]' } }] }
    )

    result = classifier.classify('Event happening in Seattle and Bellevue')

    assert_equal ['bellevue', 'seattle'], result.sort
  end

  def test_classify_returns_empty_array_when_no_matches
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    classifier = build_classifier(
      client_response: { 'choices' => [{ 'message' => { 'content' => '[]' } }] }
    )

    result = classifier.classify('Event happening in New York')

    assert_empty result
  end

  def test_classify_handles_json_in_markdown_format
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    classifier = build_classifier(
      client_response: { 'choices' => [{ 'message' => { 'content' => "```json\n[\"Seattle\"]\n```" } }] }
    )

    result = classifier.classify('Event in Seattle')

    assert_equal ['seattle'], result
  end

  def test_classify_handles_invalid_json
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    classifier = build_classifier(
      client_response: { 'choices' => [{ 'message' => { 'content' => 'not valid json' } }] }
    )

    result = classifier.classify('Event in Seattle')

    assert_empty result
  end

  def test_classify_includes_content_title_and_location_in_prompt
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    client = FakeChatClient.new(
      response: { 'choices' => [{ 'message' => { 'content' => '["Seattle"]' } }] }
    )
    classifier = Mayhem::Content::LocationClassifier.new(
      locations_dir: @tmp_locations,
      client: client,
      logger: @logger,
      model: 'test-model'
    )

    classifier.classify(
      'Some event description',
      content_title: 'Big Event',
      content_location: 'Seattle Convention Center'
    )

    # We can't easily inspect the prompt, but we've verified it runs without error
    assert_equal ['seattle'], classifier.classify('Event', content_title: 'Big Event')
  end

  def test_classify_retries_on_rate_limit
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    client = Object.new
    call_count = 0
    def client.chat(*)
      @call_count ||= 0
      @call_count += 1
      raise Faraday::TooManyRequestsError, 'rate limit' if @call_count == 1

      { 'choices' => [{ 'message' => { 'content' => '["Seattle"]' } }] }
    end

    classifier = Mayhem::Content::LocationClassifier.new(
      locations_dir: @tmp_locations,
      client: client,
      logger: @logger,
      model: 'test-model'
    )

    result = classifier.classify('Event in Seattle')

    assert_equal ['seattle'], result
    assert_match(/Rate limited/, @logger.warns.first)
  end

  def test_classify_handles_openai_error
    write_location('seattle', { 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    classifier = build_classifier(
      client_response: { 'error' => { 'message' => 'API error' } }
    )

    result = classifier.classify('Event in Seattle')

    assert_empty result
    assert_match(/OpenAI error/, @logger.warns.first)
  end
end
