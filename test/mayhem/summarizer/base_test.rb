# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'mayhem/summarizer/base'

class SummarizerBaseTest < Minitest::Test
  # Concrete implementation for testing base class behavior
  class TestSummarizer < Mayhem::Summarizer::Base
    attr_reader :records_processed

    def initialize(**kwargs)
      super
      @records_processed = []
    end

    def model_class
      @model_class ||= Class.new do
        def self.all
          []
        end
      end
    end

    attr_writer :model_class

    def process_record(record, stats)
      @records_processed << record
      stats[:processed] += 1
    end

    def log_summary(stats)
      # no-op for testing
    end

    # Expose private methods for testing
    def public_fetch_html(url)
      fetch_html(url)
    end

    def public_extract_text(html)
      extract_text(html)
    end

    def public_truncate_text(text, record_id, max_chars: MAX_ARTICLE_CHARS)
      truncate_text(text, record_id, max_chars: max_chars)
    end

    def public_classify_topics(text)
      classify_topics(text)
    end

    def public_classify_locations(text, content_title:, content_source:, content_location: nil)
      classify_locations(text, content_title: content_title, content_source: content_source, content_location: content_location)
    end

    def public_call_openai(prompt, system_message, record_id, temperature:)
      call_openai(prompt, system_message, record_id, temperature: temperature)
    end

    def public_needs_classification_for_record?(record, key)
      needs_classification_for_record?(record, key)
    end

    def public_store_source_html(record, html)
      store_source_html(record, html)
    end
  end

  def setup
    @topic_classifier = Class.new do
      def classify(_text)
        %w[topic1 topic2]
      end
    end.new

    @location_classifier = Class.new do
      def classify(_text, **)
        ['location1']
      end
    end.new
  end

  def test_run_iterates_over_model_class_all
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    model_class = Class.new do
      def self.all
        [{ id: '1' }, { id: '2' }]
      end
    end
    summarizer.model_class = model_class

    stats = summarizer.run

    assert_equal 2, stats[:processed]
    assert_equal [{ id: '1' }, { id: '2' }], summarizer.records_processed
  end

  def test_fetch_html_returns_nil_for_empty_url
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    assert_nil summarizer.public_fetch_html(nil)
    assert_nil summarizer.public_fetch_html('')
    assert_nil summarizer.public_fetch_html('   ')
  end

  def test_fetch_html_handles_errors_gracefully
    http_stub = Class.new do
      def fetch(*)
        raise StandardError, 'connection error'
      end
    end.new

    summarizer = TestSummarizer.new(
      http_client: http_stub,
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    assert_nil summarizer.public_fetch_html('http://example.com')
  end

  def test_extract_text_delegates_to_article_body_extractor
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    html = '<article><p>Hello world</p></article>'
    text = summarizer.public_extract_text(html)

    assert_includes text, 'Hello world'
  end

  def test_truncate_text_truncates_when_over_limit
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    long_text = 'a' * 100
    result = summarizer.public_truncate_text(long_text, 'test-record', max_chars: 50)

    assert_equal 50, result.length
    assert_equal 'a' * 50, result
  end

  def test_truncate_text_returns_original_when_under_limit
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    short_text = 'hello'
    result = summarizer.public_truncate_text(short_text, 'test-record', max_chars: 50)

    assert_equal short_text, result
  end

  def test_truncate_text_handles_nil
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    result = summarizer.public_truncate_text(nil, 'test-record')

    assert_nil result
  end

  def test_classify_topics_delegates_to_topic_classifier
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    result = summarizer.public_classify_topics('some text')

    assert_equal %w[topic1 topic2], result
  end

  def test_classify_locations_delegates_to_location_classifier
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    result = summarizer.public_classify_locations(
      'some text',
      content_title: 'Test Title',
      content_source: 'Test Source'
    )

    assert_equal ['location1'], result
  end

  def test_call_openai_returns_content_on_success
    client = Class.new do
      def chat(*)
        { 'choices' => [{ 'message' => { 'content' => 'Generated summary' } }] }
      end
    end.new

    summarizer = TestSummarizer.new(
      client: client,
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    result = summarizer.public_call_openai('prompt', 'system', 'record-1', temperature: 0.7)

    assert_equal 'Generated summary', result
  end

  def test_call_openai_returns_nil_on_error_message
    client = Class.new do
      def chat(*)
        { 'error' => { 'message' => 'API error' } }
      end
    end.new

    summarizer = TestSummarizer.new(
      client: client,
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    result = summarizer.public_call_openai('prompt', 'system', 'record-1', temperature: 0.7)

    assert_nil result
  end

  def test_call_openai_retries_on_rate_limit
    call_count = 0
    client = Class.new do
      define_method(:chat) do |*|
        call_count += 1
        raise Faraday::TooManyRequestsError, 'rate limited' if call_count == 1

        { 'choices' => [{ 'message' => { 'content' => 'Success after retry' } }] }
      end
    end.new

    summarizer = TestSummarizer.new(
      client: client,
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    # Override sleep to avoid actual delay
    summarizer.define_singleton_method(:sleep) { |_| nil }

    result = summarizer.public_call_openai('prompt', 'system', 'record-1', temperature: 0.7)

    assert_equal 'Success after retry', result
    assert_equal 2, call_count
  end

  def test_needs_classification_for_record_returns_true_when_nil
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      def [](_key)
        nil
      end
    end.new

    assert summarizer.public_needs_classification_for_record?(record, 'topic_titles')
  end

  def test_needs_classification_for_record_returns_false_when_empty_array
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      def [](_key)
        []
      end
    end.new

    refute summarizer.public_needs_classification_for_record?(record, 'topic_titles')
  end

  def test_needs_classification_for_record_returns_false_when_present
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      def [](_key)
        ['Health']
      end
    end.new

    refute summarizer.public_needs_classification_for_record?(record, 'topic_titles')
  end

  def test_default_model_uses_env_var
    original_model = ENV.fetch('OPENAI_MODEL', nil)
    ENV['OPENAI_MODEL'] = 'test-model'

    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    assert_equal 'test-model', summarizer.instance_variable_get(:@model)
  ensure
    if original_model
      ENV['OPENAI_MODEL'] = original_model
    else
      ENV.delete('OPENAI_MODEL')
    end
  end

  def test_model_can_be_overridden_in_constructor
    summarizer = TestSummarizer.new(
      model: 'custom-model',
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    assert_equal 'custom-model', summarizer.instance_variable_get(:@model)
  end

  def test_max_article_chars_constant
    assert_equal 20_000, Mayhem::Summarizer::Base::MAX_ARTICLE_CHARS
  end

  def test_store_source_html_sets_original_source_html_on_record
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      attr_accessor :original_source_html
    end.new

    html = '<article><p>Test content</p></article>'
    summarizer.public_store_source_html(record, html)

    assert_equal html, record.original_source_html
  end

  def test_store_source_html_does_nothing_when_html_is_nil
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      attr_accessor :original_source_html
    end.new

    summarizer.public_store_source_html(record, nil)

    assert_nil record.original_source_html
  end

  def test_store_source_html_truncates_long_content
    summarizer = TestSummarizer.new(
      topic_classifier: @topic_classifier,
      location_classifier: @location_classifier
    )

    record = Class.new do
      attr_accessor :original_source_html
    end.new

    # HTML longer than MAX_ARTICLE_CHARS should be truncated
    long_html = "<article>#{'x' * 25_000}</article>"
    summarizer.public_store_source_html(record, long_html)

    assert_equal Mayhem::Summarizer::Base::MAX_ARTICLE_CHARS, record.original_source_html.length
  end
end
