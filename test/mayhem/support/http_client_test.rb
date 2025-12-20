# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/support/http_client'

# Integration tests for HttpClient public API
# Unit tests for individual components are in the http_client/ subdirectory
class HttpClientTest < Minitest::Test
  class FakeLogger
    attr_reader :warns, :debugs

    def initialize
      @warns = []
      @debugs = []
    end

    def warn(message)
      @warns << message
    end

    def debug(message)
      @debugs << message
    end

    def info(_message); end
  end

  def setup
    @logger = FakeLogger.new
    @client = Mayhem::Support::HttpClient.new(
      logger: @logger,
      delay: 0,
      max_retries: 1,
      timeout: 1,
      open_timeout: 1,
      read_timeout: 1,
      host_operation_delays: {}
    )
  end

  # Public API: resolve_final_url

  def test_resolve_final_url_returns_successful_redirect
    @client.instance_variable_get(:@request_flow).stub(:resolve_head_redirects, { status: 200, url: 'https://final' }) do
      assert_equal 'https://final', @client.resolve_final_url('https://start')
    end
  end

  def test_resolve_final_url_returns_nil_for_non_successful_status
    @client.instance_variable_get(:@request_flow).stub(:resolve_head_redirects, { status: 400, url: 'https://start' }) do
      assert_nil @client.resolve_final_url('https://start')
      assert_match(/Skipping canonical redirect/, @logger.debugs.last)
    end
  end

  def test_resolve_final_url_handles_invalid_uri
    assert_nil @client.resolve_final_url('not valid://')
    assert_match(/Invalid URI/, @logger.debugs.last)
  end

  # Public API: response_for

  def test_response_for_returns_hash_with_status_and_url
    response = Struct.new(:code) { def [](key); nil; end }
    payload = { final_url: 'https://example.com' }
    @client.instance_variable_get(:@request_flow).stub(:fetch_with_redirects, [response.new('200'), payload]) do
      result = @client.response_for('https://example.com', accept: 'text/plain', max_bytes: 1)
      assert_equal 200, result[:status]
      assert_equal 'https://example.com', result[:final_url]
    end
  end

  def test_response_for_handles_invalid_uri
    assert_nil @client.response_for('not valid://')
    assert_match(/Invalid URI while checking status/, @logger.debugs.last)
  end

  def test_response_for_handles_not_found_error
    error = Mayhem::Support::HttpClient::NotFoundError.new(
      url: 'https://example.com',
      origin_url: 'https://example.com',
      operation: 'status_check',
      status: 404
    )
    @client.stub(:perform_request, proc { raise error }) do
      result = @client.response_for('https://example.com')
      assert_equal 404, result[:status]
      assert_equal 'https://example.com', result[:final_url]
      assert_nil result[:response]
    end
  end

  # Public API: fetch

  def test_fetch_returns_payload_body
    payload = {
      body: 'test content',
      content_type: 'text/html',
      final_url: 'https://example.com'
    }
    response = Struct.new(:code) { def [](key); nil; end }
    @client.stub(:perform_request, [response.new('200'), payload]) do
      result = @client.fetch('https://example.com', accept: 'text/html', max_bytes: 0)
      assert_equal payload, result
    end
  end

  def test_fetch_retries_on_too_many_requests
    error = Mayhem::Support::HttpClient::TooManyRequestsError.new(
      url: 'https://example.com',
      retry_after: 0.01,
      origin_url: 'https://example.com',
      operation: 'content_fetch'
    )
    
    call_count = 0
    payload = { body: 'success', content_type: 'text/html', final_url: 'https://example.com' }
    response = Struct.new(:code) { def [](key); nil; end }
    
    @client.stub(:perform_request, proc do
      call_count += 1
      raise error if call_count == 1
      [response.new('200'), payload]
    end) do
      result = @client.fetch('https://example.com', accept: 'text/html', max_bytes: 0)
      assert_equal payload, result
      assert_equal 2, call_count
    end
  end

  def test_fetch_raises_after_max_retries
    error = Mayhem::Support::HttpClient::TooManyRequestsError.new(
      url: 'https://example.com',
      retry_after: 0.01,
      origin_url: 'https://example.com',
      operation: 'content_fetch'
    )
    
    @client.stub(:perform_request, proc { raise error }) do
      assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
        @client.fetch('https://example.com', accept: 'text/html', max_bytes: 0)
      end
    end
  end
end
