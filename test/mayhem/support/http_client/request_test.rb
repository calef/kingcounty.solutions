# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require_relative '../../../../lib/mayhem/support/http_client'
require_relative 'test_helpers'

module Mayhem
  module Support
    class HttpClient
      class RequestTest < Minitest::Test
        include HttpClientTestHelpers

        class FakeDelayManager
          def apply_delay(_operation, _uri); end
        end

        def setup
          @logger = HttpClientTestHelpers::FakeLogger.new
          @transport = Mayhem::Support::HttpClient::HttpTransport.new(
            user_agent: Mayhem::Support::HttpClient::UA,
            open_timeout: 1,
            read_timeout: 1,
            allow_insecure_fallback: true,
            logger: @logger,
            operation_delay_manager: FakeDelayManager.new
          )
        end

        def test_perform_http_head_uses_net_http_connection
          response = HttpClientTestHelpers::FakeResponse.new('200', {})
          fake_http = HttpClientTestHelpers::FakeHttp.new(response)
          Net::HTTP.stub(:new, ->(_host, _port) { fake_http }) do
            result = @transport.execute_head(URI('https://example.com'))
            assert_equal response, result
            assert fake_http.started
            assert_instance_of Net::HTTP::Head, fake_http.last_request
          end
        end

        def test_execute_request_retries_without_verification
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @transport.stub(:perform_http_request, proc { |_uri, _accept, _verify_mode| raise error }) do
            @transport.stub(:retry_without_verification, proc { called = true; [:retry] }) do
              assert_equal [:retry], @transport.execute_get(URI('https://example.com'), 'text/html')
              assert called
            end
          end
        end

        def test_execute_head_request_retries_without_verification_head
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @transport.stub(:perform_http_head, proc { |_uri, _verify_mode| raise error }) do
            @transport.stub(:retry_without_verification_head, proc { called = true; :rehead }) do
              assert_equal :rehead, @transport.execute_head(URI('https://example.com'))
              assert called
            end
          end
        end

        def test_retry_without_verification_logs_and_retries_only_when_allowed
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @transport.stub(:perform_http_request, proc { called = true; [:retried] }) do
            assert_equal [:retried], @transport.send(:retry_without_verification, URI('https://example.com'), 'text/html', error)
            assert called
          end

          denial_transport = Mayhem::Support::HttpClient::HttpTransport.new(
            user_agent: Mayhem::Support::HttpClient::UA,
            open_timeout: 1,
            read_timeout: 1,
            allow_insecure_fallback: false,
            logger: @logger,
            operation_delay_manager: FakeDelayManager.new
          )
          assert_raises(OpenSSL::SSL::SSLError) do
            denial_transport.send(:retry_without_verification, URI('https://example.com'), 'text/html', error)
          end
        end

        def test_build_request_sets_headers
          uri = URI('https://example.com/path')
          request = @transport.send(:build_request, uri, 'application/json')

          assert_equal Mayhem::Support::HttpClient::UA, request['User-Agent']
          assert_equal 'application/json', request['Accept']
          assert_equal 'identity', request['Accept-Encoding']
        end

        def test_build_head_request_sets_user_agent
          uri = URI('https://example.com/path')
          request = @transport.send(:build_head_request, uri)

          assert_equal Mayhem::Support::HttpClient::UA, request['User-Agent']
        end
      end
    end
  end
end
