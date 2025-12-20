# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require_relative '../../../../lib/mayhem/support/http_client'

module Mayhem
  module Support
    module HttpClient
      class RequestTest < Minitest::Test
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
          def initialize(code, headers = {})
            @code = code
            @headers = headers
          end

          def code
            @code
          end

          def [](key)
            @headers[key]
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

        def test_perform_http_head_uses_net_http_connection
          response = FakeResponse.new('200', {})
          fake_http = FakeHttp.new(response)
          Net::HTTP.stub(:new, ->(_host, _port) { fake_http }) do
            result = @client.send(:perform_http_head, URI('https://example.com'), OpenSSL::SSL::VERIFY_PEER)
            assert_equal response, result
            assert fake_http.started
          end
        end

        def test_execute_request_retries_without_verification
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @client.stub(:perform_http_request, proc { |_uri, _accept, _max_bytes, _verify_mode| raise error }) do
            @client.stub(:retry_without_verification, proc { called = true; [:retry] }) do
              assert_equal [:retry], @client.send(:execute_request, URI('https://example.com'), 'text/html', 0)
              assert called
            end
          end
        end

        def test_execute_head_request_retries_without_verification_head
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @client.stub(:perform_http_head, proc { |_uri, _verify_mode| raise error }) do
            @client.stub(:retry_without_verification_head, proc { called = true; :rehead }) do
              assert_equal :rehead, @client.send(:execute_head_request, URI('https://example.com'))
              assert called
            end
          end
        end

        def test_retry_without_verification_logs_and_retries_only_when_allowed
          error = OpenSSL::SSL::SSLError.new('boom')
          called = false
          @client.stub(:execute_request, proc { called = true; [:retried] }) do
            assert_equal [:retried], @client.send(:retry_without_verification, URI('https://example.com'), 'text/html', 0, false, error, operation: 'op')
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
          assert_raises(OpenSSL::SSL::SSLError) do
            denial_client.send(:retry_without_verification, URI('https://example.com'), 'text/html', 0, false, error, operation: 'op')
          end
        end

        def test_build_request_sets_headers
          uri = URI('https://example.com/path')
          request = @client.send(:build_request, uri, 'application/json')
          
          assert_equal Mayhem::Support::HttpClient::UA, request['User-Agent']
          assert_equal 'application/json', request['Accept']
          assert_equal 'identity', request['Accept-Encoding']
        end

        def test_build_head_request_sets_user_agent
          uri = URI('https://example.com/path')
          request = @client.send(:build_head_request, uri)
          
          assert_equal Mayhem::Support::HttpClient::UA, request['User-Agent']
        end
      end
    end
  end
end
