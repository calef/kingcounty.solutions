# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/location_relevance_checker'

class LocationRelevanceCheckerTest < Minitest::Test
  def setup
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
  end

  def test_returns_true_when_openai_responds_yes
    client = Object.new
    def client.chat(parameters:)
      { 'choices' => [{ 'message' => { 'content' => 'yes' } }] }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    result = checker.relevant_to_king_county?(
      title: 'Seattle Community Event',
      content: 'Join us in Seattle for a community gathering.'
    )

    assert result
  end

  def test_returns_false_when_openai_responds_no
    client = Object.new
    def client.chat(parameters:)
      { 'choices' => [{ 'message' => { 'content' => 'no' } }] }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    result = checker.relevant_to_king_county?(
      title: 'New York Event',
      content: 'This event is happening in New York City.'
    )

    refute result
  end

  def test_returns_true_when_openai_errors
    client = Object.new
    def client.chat(parameters:)
      { 'error' => { 'message' => 'API Error' } }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    result = checker.relevant_to_king_county?(
      title: 'Some Event',
      content: 'Some content'
    )

    assert result
  end

  def test_retries_on_rate_limit_error
    client = Object.new
    client_singleton = class << client; self; end
    client_singleton.send(:define_method, :chat) do |parameters:|
      @__calls ||= 0
      if @__calls.zero?
        @__calls += 1
        raise Faraday::TooManyRequestsError, 'rate limit'
      end
      { 'choices' => [{ 'message' => { 'content' => 'yes' } }] }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    result = checker.relevant_to_king_county?(
      title: 'Event',
      content: 'Content'
    )

    assert result
  end

  def test_includes_location_in_prompt_when_provided
    client = Object.new
    def client.chat(parameters:)
      @captured_messages = parameters[:messages]
      { 'choices' => [{ 'message' => { 'content' => 'yes' } }] }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    checker.relevant_to_king_county?(
      title: 'Event',
      content: 'Content',
      location: 'Seattle, WA'
    )

    captured_messages = client.instance_variable_get(:@captured_messages)
    user_message = captured_messages.find { |m| m[:role] == 'user' }
    assert user_message[:content].include?('Location: Seattle, WA')
  end

  def test_truncates_long_content
    client = Object.new
    def client.chat(parameters:)
      { 'choices' => [{ 'message' => { 'content' => 'yes' } }] }
    end

    checker = Mayhem::Support::LocationRelevanceChecker.new(client: client, logger: @logger)
    long_content = 'x' * 5000

    result = checker.relevant_to_king_county?(
      title: 'Event',
      content: long_content
    )

    assert result
  end
end
