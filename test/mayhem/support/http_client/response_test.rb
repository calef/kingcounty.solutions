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
        end

        def test_follow_head_redirect_follows_multiple_hops
          first = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/final' }, redirect: true)
          second = HttpClientTestHelpers::FakeResponse.new('200', {}, redirect: false)
          responses = [first, second]

          @client.stub(:execute_head_request, proc { |_uri, **_| responses.shift }) do
            result = @client.send(
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
          response = HttpClientTestHelpers::FakeResponse.new('429', { 'retry-after' => '5' })
          @client.stub(:parse_retry_after, 5) do
            assert_equal 5, @client.send(:too_many_requests_delay, response)
          end
          @client.stub(:parse_retry_after, 0) do
            assert_equal 60, @client.send(:too_many_requests_delay, response)
          end
        end

        def test_parse_retry_after_handles_numeric_httpdate_and_invalid
          assert_equal 5, @client.send(:parse_retry_after, '5')

          now = Time.now
          Time.stub(:now, now) do
            header = (now + 5).httpdate
            assert_equal 5, @client.send(:parse_retry_after, header)
          end

          assert_nil @client.send(:parse_retry_after, 'not-a-date')
        end

        def test_perform_request_follows_redirect
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          @client.stub(:execute_request, [response, {}]) do
            redirected = false
            @client.stub(:follow_redirect, proc { |*_| redirected = true; :redirected }) do
              result = @client.send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
              assert redirected
              assert_equal :redirected, result
            end
          end
        end

        def test_perform_request_raises_on_too_many_requests
          response = HttpClientTestHelpers::FakeResponse.new('429', {})
          @client.stub(:execute_request, [response, {}]) do
            assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
              @client.send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
            end
          end
        end

        def test_follow_redirect_requires_location_and_limit
          response = HttpClientTestHelpers::FakeResponse.new('301', {}, redirect: true)
          assert_raises(RuntimeError) do
            @client.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
          end

          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com' }, redirect: true)
          assert_raises(RuntimeError) do
            @client.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 0, 0, origin_url: 'origin', operation: 'op')
          end
        end

        def test_follow_redirect_calls_perform_request_with_absolutized_url
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => '/next' }, redirect: true)
          Mayhem::Support::UrlUtils.stub(:absolutize, 'https://example.com/absolute') do
            performed = false
            @client.stub(:perform_request, proc { performed = true; :visited }) do
              assert_equal :visited, @client.send(:follow_redirect, response, URI('https://example.com'), 'text/html', 1, 1, origin_url: 'origin', operation: 'op')
              assert performed
            end
          end
        end

        def test_follow_head_redirect_handles_too_many_requests_and_missing_location
          error_response = HttpClientTestHelpers::FakeResponse.new('429', {})
          @client.stub(:execute_head_request, proc { |_uri, **_| error_response }) do
            assert_raises(Mayhem::Support::HttpClient::TooManyRequestsError) do
              @client.send(:follow_head_redirect, URI('https://example.com'), 1, origin_url: 'origin', operation: 'op')
            end
          end

          redirect_response = HttpClientTestHelpers::FakeResponse.new('301', {}, redirect: true)
          @client.stub(:execute_head_request, proc { |_uri, **_| redirect_response }) do
            assert_equal({ url: 'https://example.com', status: 301 }, @client.send(:follow_head_redirect, URI('https://example.com'), 1, origin_url: 'origin', operation: 'op'))
          end
        end

        def test_follow_head_redirect_respects_remaining_redirects
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          @client.stub(:execute_head_request, proc { |_uri, **_| response }) do
            assert_raises(RuntimeError) do
              @client.send(:follow_head_redirect, URI('https://example.com'), 0, origin_url: 'origin', operation: 'op')
            end
          end
        end

        def test_perform_request_redirects_when_response_is_redirection
          response = HttpClientTestHelpers::FakeResponse.new('301', { 'location' => 'https://example.com/next' }, redirect: true)
          @client.stub(:execute_request, [response, {}]) do
            redirected = false
            @client.stub(:follow_redirect, proc { redirected = true; :sent }) do
              result = @client.send(:perform_request, 'https://example.com', 'text/html', 2, 2, origin_url: 'https://example.com', operation: 'op')
              assert redirected
              assert_equal :sent, result
            end
          end
        end
      end
    end
  end
end
