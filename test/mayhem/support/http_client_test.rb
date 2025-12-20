# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'time'
require_relative '../../../lib/mayhem/support/http_client'

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

  class FakeResponse
    def initialize(code, headers = {}, redirect: false)
      @code = code
      @headers = headers
      @redirect = redirect
    end

    def code
      @code
    end

    def [](key)
      @headers[key]
    end

    def is_a?(klass)
      return true if klass == Net::HTTPRedirection && @redirect

      super
    end
  end

  class FakeHttp
    attr_reader :started, :request
    attr_accessor :use_ssl, :read_timeout, :open_timeout, :verify_mode, :cert_store

    def initialize(response)
      @response = response
      @started = false
    end

    def start
      @started = true
      yield self
    end

    def request(_request)
      @request = _request
      @response
    end

    def use_ssl?
      !!@use_ssl
    end
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

  def test_resolve_final_url_returns_successful_redirect
    @client.instance_variable_get(:@response).stub(:resolve_head_redirects, { status: 200, url: 'https://final' }) do
      assert_equal 'https://final', @client.resolve_final_url('https://start')
    end
  end

  def test_resolve_final_url_returns_nil_for_non_successful_status
    @client.instance_variable_get(:@response).stub(:resolve_head_redirects, { status: 400, url: 'https://start' }) do
      assert_nil @client.resolve_final_url('https://start')
      assert_match(/Skipping canonical redirect/, @logger.debugs.last)
    end
  end

  def test_response_for_returns_hash_with_status_and_url
    response = Struct.new(:code) { def [](key); nil; end }
    payload = { final_url: 'https://example.com' }
    @client.instance_variable_get(:@response).stub(:fetch_with_redirects, [response.new('200'), payload]) do
      result = @client.response_for('https://example.com', accept: 'text/plain', max_bytes: 1)
      assert_equal 200, result[:status]
      assert_equal 'https://example.com', result[:final_url]
    end
  end

  def test_perform_http_head_uses_net_http_connection
    response = FakeResponse.new('200', {})
    fake_http = FakeHttp.new(response)
    Net::HTTP.stub(:new, ->(_host, _port) { fake_http }) do
      result = @client.instance_variable_get(:@request).send(:perform_http_head, URI('https://example.com'), OpenSSL::SSL::VERIFY_PEER)
      assert_equal response, result
      assert fake_http.started
    end
  end

  def test_follow_head_redirect_follows_multiple_hops
    first = FakeResponse.new('301', { 'location' => 'https://example.com/final' }, redirect: true)
    second = FakeResponse.new('200', {}, redirect: false)
    responses = [first, second]

    request = @client.instance_variable_get(:@request)
    request.stub(:execute_head, proc { |_uri, **_| responses.shift }) do
      result = @client.instance_variable_get(:@response).send(
        :follow_head_redirect,
        URI('https://example.com/start'),
        3,
        origin_url: 'https://origin',
        operation: 'canonical_head'
      )
      assert_equal 'https://example.com/final', result[:url]
      assert_equal 200, result[:status]
    end
  end

  def test_log_too_many_requests_backoff_includes_details
    error = Mayhem::Support::HttpClient::TooManyRequestsError.new(
      url: 'https://example.com/fail',
      retry_after: 10,
      origin_url: 'https://origin',
      operation: 'content_fetch'
    )
    @client.send(:log_too_many_requests_backoff, error, 10, attempt: 1, max_attempts: 3)
    message = @logger.warns.last
    assert_includes message, 'Backoff after 429'
    assert_includes message, 'content_fetch'
  end

  def test_too_many_requests_delay_respects_parse_result_and_minimum
    response = FakeResponse.new('429', { 'retry-after' => '5' })
    response_handler = @client.instance_variable_get(:@response)
    response_handler.stub(:parse_retry_after, 5) do
      assert_equal 5, response_handler.send(:too_many_requests_delay, response)
    end
    response_handler.stub(:parse_retry_after, 0) do
      assert_equal 60, response_handler.send(:too_many_requests_delay, response)
    end
  end

  def test_parse_retry_after_handles_numeric_httpdate_and_invalid
    response_handler = @client.instance_variable_get(:@response)
    assert_equal 5, response_handler.send(:parse_retry_after, '5')

    now = Time.now
    Time.stub(:now, now) do
      header = (now + 5).httpdate
      assert_equal 5, response_handler.send(:parse_retry_after, header)
    end

    assert_nil response_handler.send(:parse_retry_after, 'not-a-date')
  end

  def test_perform_request_follows_redirect
    response = FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
    request = @client.instance_variable_get(:@request)
    request.stub(:execute_get, [response, {}]) do
      redirected = false
      response_handler = @client.instance_variable_get(:@response)
      response_handler.stub(:follow_redirect, proc { |*_| redirected = true; :redirected }) do
        result = response_handler.send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
        assert redirected
        assert_equal :redirected, result
      end
    end
  end

  def test_perform_request_raises_on_too_many_requests
    response = FakeResponse.new('429', {})
    request = @client.instance_variable_get(:@request)
    request.stub(:execute_get, [response, {}]) do
      assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
        @client.instance_variable_get(:@response).send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
      end
    end
  end

  def test_execute_request_retries_without_verification
    error = OpenSSL::SSL::SSLError.new('boom')
    called = false
    request = @client.instance_variable_get(:@request)
    request.stub(:perform_http_request, proc { |_uri, _accept, _max_bytes, _verify_mode| raise error }) do
      request.stub(:retry_without_verification, proc { called = true; [:retry] }) do
        assert_equal [:retry], request.send(:execute_get, URI('https://example.com'), 'text/html', 0)
        assert called
      end
    end
  end

  def test_execute_head_request_retries_without_verification_head
    error = OpenSSL::SSL::SSLError.new('boom')
    called = false
    request = @client.instance_variable_get(:@request)
    request.stub(:perform_http_head, proc { |_uri, _verify_mode| raise error }) do
      request.stub(:retry_without_verification_head, proc { called = true; :rehead }) do
        assert_equal :rehead, request.send(:execute_head, URI('https://example.com'))
        assert called
      end
    end
  end

  def test_follow_redirect_requires_location_and_limit
    response = FakeResponse.new('301', {}, redirect: true)
    response_handler = @client.instance_variable_get(:@response)
    assert_raises(RuntimeError) do
      response_handler.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
    end

    response = FakeResponse.new('301', { 'location' => 'https://example.com' }, redirect: true)
    assert_raises(RuntimeError) do
      response_handler.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 0, 0, origin_url: 'origin', operation: 'op')
    end
  end

  def test_follow_redirect_calls_perform_request_with_absolutized_url
    response = FakeResponse.new('301', { 'location' => '/next' }, redirect: true)
    Mayhem::Support::UrlUtils.stub(:absolutize, 'https://example.com/absolute') do
      performed = false
      response_handler = @client.instance_variable_get(:@response)
      response_handler.stub(:perform_request, proc { performed = true; :visited }) do
        assert_equal :visited, response_handler.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
        assert performed
      end
    end
  end

  def test_follow_head_redirect_handles_too_many_requests_and_missing_location
    error_response = FakeResponse.new('429', {})
    request = @client.instance_variable_get(:@request)
    request.stub(:execute_head, proc { |_uri, **_| error_response }) do
      assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
        @client.instance_variable_get(:@response).send(:follow_head_redirect, URI('https://example.com'), 1, origin_url: 'origin', operation: 'op')
      end
    end

    redirect_response = FakeResponse.new('301', {}, redirect: true)
    request.stub(:execute_head, proc { |_uri, **_| redirect_response }) do
      assert_equal({ url: 'https://example.com', status: 301 }, @client.instance_variable_get(:@response).send(:follow_head_redirect, URI('https://example.com'), 1, origin_url: 'origin', operation: 'op'))
    end
  end

  def test_follow_head_redirect_respects_remaining_redirects
    response = FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
    request = @client.instance_variable_get(:@request)
    request.stub(:execute_head, proc { |_uri, **_| response }) do
      assert_raises(RuntimeError) do
        @client.instance_variable_get(:@response).send(:follow_head_redirect, URI('https://example.com'), 0, origin_url: 'origin', operation: 'op')
      end
    end
  end

  def test_retry_without_verification_logs_and_retries_only_when_allowed
    error = OpenSSL::SSL::SSLError.new('boom')
    called = false
    request = @client.instance_variable_get(:@request)
    request.stub(:perform_http_request, proc { called = true; [:retried] }) do
      assert_equal [:retried], request.send(:retry_without_verification, URI('https://example.com'), 'text/html', 0, error, operation: 'op')
      assert called
    end

    denial_client = Mayhem::Support::HttpClient.new(
      logger: @logger,
      delay: 0,
      max_retries: 1,
      timeout: 1,
      open_timeout: 1,
      read_timeout: 1,
      allow_insecure_fallback: false,
      host_operation_delays: {}
    )
    denial_request = denial_client.instance_variable_get(:@request)
    assert_raises(OpenSSL::SSL::SSLError) do
      denial_request.send(:retry_without_verification, URI('https://example.com'), 'text/html', 0, error, operation: 'op')
    end
  end

  def test_resolve_final_url_handles_invalid_uri
    assert_nil @client.resolve_final_url('not valid://')
    assert_match(/Invalid URI/, @logger.debugs.last)
  end

  def test_response_for_handles_invalid_uri
    assert_nil @client.response_for('not valid://')
    assert_match(/Invalid URI while checking status/, @logger.debugs.last)
  end

  def test_perform_request_redirects_when_response_is_redirection
    response = FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
    request = @client.instance_variable_get(:@request)
    request.stub(:execute_get, [response, {}]) do
      redirected = false
      response_handler = @client.instance_variable_get(:@response)
      response_handler.stub(:follow_redirect, proc { redirected = true; :sent }) do
        result = response_handler.send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
        assert redirected
        assert_equal :sent, result
      end
    end
  end
end
