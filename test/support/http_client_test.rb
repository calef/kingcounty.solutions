# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'uri'
require_relative '../../lib/mayhem/support/http_client'
require_relative '../../lib/mayhem/logging'

class HttpClientTest < Minitest::Test
  class DummyResponse
    attr_reader :headers, :code

    def initialize(body_chunks, code: '200', headers: {})
      @body_chunks = body_chunks
      @code = code
      @headers = headers
      @code = code
    end

    def [](k)
      @headers[k]
    end

    def read_body(&)
      @body_chunks.each(&)
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

    def request(_req)
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
    chunks = %w[hello world]
    response = DummyResponse.new(chunks)
    body = @client.send(:read_response_body, response, 7)

    assert_equal 'hellowo'.dup.force_encoding('BINARY'), body
  end

  def test_follow_redirect_and_final_url
    redir = DummyResponse.new([], code: '302', headers: { 'location' => 'https://example.com/final' })
    final = DummyResponse.new(['ok'], headers: { 'content-type' => 'text/plain' })

    # stub execute_request to return redirection then final
    called = 0
    @client.define_singleton_method(:execute_request) do |_uri, _accept, _max_bytes, verify_mode: nil, retried: false, operation: nil|
      called += 1
      if called == 1
        [redir, '']
      else
        [final, 'ok']
      end
    end

    response, payload = @client.send(
      :perform_request,
      'http://example.com',
      'text/plain',
      10,
      5,
      origin_url: 'http://example.com',
      operation: 'test'
    )

    assert_equal 'ok', payload[:body]
    assert_equal 'https://example.com/final', payload[:final_url]
  end

  def test_missing_location_raises
    redir = DummyResponse.new([], code: '302', headers: {})
    @client.define_singleton_method(:execute_request) { |*| [redir, ''] }
    assert_raises(RuntimeError) do
      @client.send(
        :follow_redirect,
        redir,
        URI.parse('http://a'),
        'text/plain',
        10,
        1,
        origin_url: 'http://origin',
        operation: 'test'
      )
    end
  end

  def test_too_many_redirects_raises
    redir = DummyResponse.new([], code: '302', headers: { 'location' => 'x' })
    assert_raises(RuntimeError) do
      @client.send(
        :follow_redirect,
        redir,
        URI.parse('http://a'),
        'text/plain',
        10,
        0,
        origin_url: 'http://origin',
        operation: 'test'
      )
    end
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
    @client = Mayhem::Support::HttpClient.new(allow_insecure_fallback: false,
                                              logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
    @client.define_singleton_method(:perform_http_request) { |*| raise err }
    assert_raises(OpenSSL::SSL::SSLError) { @client.send(:execute_request, URI.parse('https://a'), 'text/plain', 10) }
  end

  def test_build_request_headers
    req = @client.send(:build_request, URI.parse('http://x'), 'text/html')

    assert_equal Mayhem::Support::HttpClient::UA, req['User-Agent']
    assert_equal 'text/html', req['Accept']
    assert_equal 'identity', req['Accept-Encoding']
  end

  def test_operation_host_delay_applies_only_to_matching_operation_and_host
    sleeps = []
    client = Mayhem::Support::HttpClient.new(
      host_operation_delays: {
        'canonical_head' => { 'example.com' => 0.05 }
      },
      logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    )
    client.define_singleton_method(:sleep) do |duration|
      sleeps << duration
      0
    end

    uri = URI.parse('https://example.com/article')
    client.send(:apply_operation_delay, 'canonical_head', uri)
    client.send(:apply_operation_delay, 'canonical_head', uri)

    assert_equal 1, sleeps.length
    assert_operator sleeps.first, :>, 0

    other_uri = URI.parse('https://other.com/article')
    client.send(:apply_operation_delay, 'canonical_head', other_uri)
    client.send(:apply_operation_delay, 'content_fetch', uri)

    assert_equal 1, sleeps.length
  end

  def test_env_configures_default_pubmed_canonical_head_delay
    previous = ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY']
    ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = '0.25'
    client = Mayhem::Support::HttpClient.new(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))

    delays = client.instance_variable_get(:@operation_host_delays)
    assert_in_delta 0.25, delays.fetch('canonical_head').fetch('pubmed.ncbi.nlm.nih.gov'), 0.0001
  ensure
    if previous.nil?
      ENV.delete('RSS_PUBMED_CANONICAL_HEAD_DELAY')
    else
      ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = previous
    end
  end

  def test_env_zero_disables_default_pubmed_delay
    previous = ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY']
    ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = '0'
    client = Mayhem::Support::HttpClient.new(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))

    assert_equal({}, client.instance_variable_get(:@operation_host_delays))
  ensure
    if previous.nil?
      ENV.delete('RSS_PUBMED_CANONICAL_HEAD_DELAY')
    else
      ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = previous
    end
  end
end
