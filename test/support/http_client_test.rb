# frozen_string_literal: true
require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/http_client'
require_relative '../../lib/mayhem/logging'

class HttpClientTest < Minitest::Test
  class DummyResponse
    attr_reader :headers
    def initialize(body_chunks, code: '200', headers: {})
      @body_chunks = body_chunks
      @code = code
      @headers = headers
    end

    def [](k)
      @headers[k]
    end

    def read_body
      @body_chunks.each { |c| yield c }
    end

    def is_a?(cls)
      return false unless cls == Net::HTTPRedirection
      @code.start_with?('3')
    end
  end

  class DummyConnection
    def initialize(response)
      @response = response
    end

    def request(req)
      yield @response if block_given?
      @response
    end
  end

  class DummyHttp
    attr_accessor :use_ssl, :verify_mode, :cert_store, :read_timeout, :open_timeout
    def initialize(connection)
      @connection = connection
    end

    def start
      yield @connection
    end
  end

  def setup
    @client = Mayhem::Support::HttpClient.new(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
  end

  def test_read_response_body_truncates
    chunks = ['hello', 'world']
    response = DummyResponse.new(chunks)
    body = @client.send(:read_response_body, response, 7)
    assert_equal 'hellowo'.dup.force_encoding('BINARY'), body
  end

  def test_follow_redirect_and_final_url
    redir = DummyResponse.new([], code: '302', headers: { 'location' => 'https://example.com/final' })
    final = DummyResponse.new(['ok'], headers: { 'content-type' => 'text/plain' })

    # stub execute_request to return redirection then final
    called = 0
    @client.define_singleton_method(:execute_request) do |uri, accept, max_bytes, verify_mode: nil, retried: false|
      called += 1
      if called == 1
        [redir, '']
      else
        [final, 'ok']
      end
    end

    result = @client.send(:perform_request, 'http://example.com', 'text/plain', 10, 5)
    assert_equal 'ok', result[:body]
    assert_equal 'https://example.com/final', result[:final_url]
  end

  def test_missing_location_raises
    redir = DummyResponse.new([], code: '302', headers: {})
    @client.define_singleton_method(:execute_request) { |*| [redir, ''] }
    assert_raises(RuntimeError) { @client.send(:follow_redirect, redir, URI.parse('http://a'), 'text/plain', 10, 1) }
  end

  def test_too_many_redirects_raises
    redir = DummyResponse.new([], code: '302', headers: { 'location' => 'x' })
    assert_raises(RuntimeError) { @client.send(:follow_redirect, redir, URI.parse('http://a'), 'text/plain', 10, 0) }
  end

  def test_retry_without_verification_and_terminal
    err = OpenSSL::SSL::SSLError.new('bad cert')
    # simulate perform_http_request raising SSLError first
    called = 0
    @client.define_singleton_method(:perform_http_request) do |*|
      called += 1
      raise err if called == 1
      [DummyResponse.new(['ok'], headers: { 'content-type' => 'text/plain' }), 'ok']
    end

    result = @client.send(:execute_request, URI.parse('https://a'), 'text/plain', 10)
    assert_equal 'ok', result.last

    # now simulate terminal when fallback disabled
    @client = Mayhem::Support::HttpClient.new(allow_insecure_fallback: false, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
    @client.define_singleton_method(:perform_http_request) { |*| raise err }
    assert_raises(OpenSSL::SSL::SSLError) { @client.send(:execute_request, URI.parse('https://a'), 'text/plain', 10) }
  end

  def test_build_request_headers
    req = @client.send(:build_request, URI.parse('http://x'), 'text/html')
    assert_equal Mayhem::Support::HttpClient::UA, req['User-Agent']
    assert_equal 'text/html', req['Accept']
    assert_equal 'identity', req['Accept-Encoding']
  end
end
