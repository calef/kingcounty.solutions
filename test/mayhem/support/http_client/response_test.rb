# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require 'time'
require_relative '../../../../lib/mayhem/support/http_client'
require_relative 'test_helpers'

module Mayhem
  module Support
    class HttpClient
      class ResponseTest < Minitest::Test
        include HttpClientTestHelpers

        def setup
          @logger = HttpClientTestHelpers::FakeLogger.new
          @client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            max_retries: 1,
            timeout: 1,
            open_timeout: 1,
            read_timeout: 1,
            host_operation_delays: {}
          )
          @response_processor = Mayhem::Support::HttpClient::ResponseProcessor.new(
            too_many_requests_delay: Mayhem::Support::HttpClient::DEFAULTS[:too_many_requests_delay],
            logger: @logger
          )
        end

        def build_request_flow(transport, max_redirects: 3)
          Mayhem::Support::HttpClient::RequestFlow.new(
            transport: transport,
            response_processor: @response_processor,
            max_redirects: max_redirects,
            logger: @logger
          )
        end

        def test_follow_head_redirect_follows_multiple_hops
          first = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/final' }, redirect: true)
          second = HttpClientTestHelpers::FakeResponse.new('200', {}, redirect: false)
          responses = [first, second]
          transport = Object.new
          transport.define_singleton_method(:execute_head) { |_uri, operation: nil| responses.shift }

          request_flow = build_request_flow(transport, max_redirects: 3)
          result = request_flow.resolve_head_redirects(
            URI('https://example.com/start'),
            origin_url: 'https://origin',
            operation: 'canonical_head'
          )
          assert_equal 'https://example.com/final', result[:url]
          assert_equal 200, result[:status]
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
          response = HttpClientTestHelpers::FakeResponse.new('429', { 'retry-after' => '5' })
          @response_processor.stub(:parse_retry_after_value, 5) do
            assert_equal 5, @response_processor.parse_retry_after(response)
          end
          @response_processor.stub(:parse_retry_after_value, 0) do
            assert_equal 60, @response_processor.parse_retry_after(response)
          end
        end

        def test_parse_retry_after_handles_numeric_httpdate_and_invalid
          response = HttpClientTestHelpers::FakeResponse.new('429', { 'retry-after' => '5' })
          assert_equal 5, @response_processor.parse_retry_after(response)

          now = Time.now
          Time.stub(:now, now) do
            header = (now + 5).httpdate
            response = HttpClientTestHelpers::FakeResponse.new('429', { 'retry-after' => header })
            assert_equal 5, @response_processor.parse_retry_after(response)
          end

          response = HttpClientTestHelpers::FakeResponse.new('429', { 'retry-after' => 'not-a-date' })
          assert_equal 60, @response_processor.parse_retry_after(response)
        end

        def test_perform_request_follows_redirect
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 2)
          redirected = false
          request_flow.stub(:follow_redirect, proc { |*_| redirected = true; :redirected }) do
            result = request_flow.fetch_with_redirects('https://example.com', 'text/html', 2, origin_url: 'https://example.com', operation: 'op')
            assert redirected
            assert_equal :redirected, result
          end
        end

        def test_perform_request_raises_on_too_many_requests
          response = HttpClientTestHelpers::FakeResponse.new('429', {})
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 2)
          assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
            request_flow.fetch_with_redirects('https://example.com', 'text/html', 2, origin_url: 'https://example.com', operation: 'op')
          end
        end

        def test_perform_request_raises_on_forbidden
          response = HttpClientTestHelpers::FakeResponse.new('403', {})
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 2)
          assert_raises(Mayhem::Support::HttpClient::ForbiddenError) do
            request_flow.fetch_with_redirects('https://example.com', 'text/html', 2, origin_url: 'https://example.com', operation: 'op')
          end
        end

        def test_follow_redirect_requires_location_and_limit
          response = HttpClientTestHelpers::FakeResponse.new('301', {}, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 1)
          assert_raises(RuntimeError) do
            request_flow.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
          end

          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com' }, redirect: true)
          assert_raises(RuntimeError) do
            request_flow.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 0, 0, origin_url: 'origin', operation: 'op')
          end
        end

        def test_follow_redirect_calls_perform_request_with_absolutized_url
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => '/next' }, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 1)
          Mayhem::Support::UrlUtils.stub(:absolutize, 'https://example.com/absolute') do
            performed = false
            request_flow.stub(:perform_request, proc { performed = true; :visited }) do
              assert_equal :visited, request_flow.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
              assert performed
            end
          end
        end

        def test_follow_head_redirect_handles_too_many_requests_and_missing_location
          error_response = HttpClientTestHelpers::FakeResponse.new('429', {})
          transport = Object.new
          transport.define_singleton_method(:execute_head) { |_uri, operation: nil| error_response }
          request_flow = build_request_flow(transport, max_redirects: 1)
          assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
            request_flow.resolve_head_redirects(URI('https://example.com'), origin_url: 'origin', operation: 'op')
          end

          redirect_response = HttpClientTestHelpers::FakeResponse.new('301', {}, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_head) { |_uri, operation: nil| redirect_response }
          request_flow = build_request_flow(transport, max_redirects: 1)
          assert_equal({ url: 'https://example.com', status: 301 }, request_flow.resolve_head_redirects(URI('https://example.com'), origin_url: 'origin', operation: 'op'))
        end

        def test_follow_head_redirect_respects_remaining_redirects
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_head) { |_uri, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 0)
          assert_raises(RuntimeError) do
            request_flow.send(:follow_head_redirect, URI('https://example.com'), 0, origin_url: 'origin', operation: 'op')
          end
        end

        def test_perform_request_redirects_when_response_is_redirection
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          transport = Object.new
          transport.define_singleton_method(:execute_get) { |_uri, _accept, operation: nil| response }
          request_flow = build_request_flow(transport, max_redirects: 2)
          redirected = false
          request_flow.stub(:follow_redirect, proc { redirected = true; :sent }) do
            result = request_flow.fetch_with_redirects('https://example.com', 'text/html', 2, origin_url: 'https://example.com', operation: 'op')
            assert redirected
            assert_equal :sent, result
          end
        end
      end
    end
  end
end
