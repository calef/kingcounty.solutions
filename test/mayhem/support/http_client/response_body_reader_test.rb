# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require_relative '../../../../lib/mayhem/support/http_client'

module Mayhem
  module Support
    module HttpClient
      class ResponseBodyReaderTest < Minitest::Test
        class FakeLogger
          def warn(_message); end
          def debug(_message); end
          def info(_message); end
        end

        class FakeResponseStream
          def initialize(chunks)
            @chunks = chunks
          end

          def read_body
            @chunks.each { |chunk| yield chunk }
          end
        end

        def setup
          @logger = FakeLogger.new
          @client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            max_retries: 1,
            timeout: 1,
            host_operation_delays: {}
          )
        end

        def test_read_response_body_returns_full_body_when_max_bytes_is_zero
          response = FakeResponseStream.new(['Hello', ' ', 'World'])
          body = @client.send(:read_response_body, response, 0)
          
          assert_equal 'Hello World', body
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_limits_to_max_bytes
          response = FakeResponseStream.new(['Hello', ' ', 'World'])
          body = @client.send(:read_response_body, response, 7)
          
          assert_equal 'Hello W', body
          assert_equal 7, body.bytesize
        end

        def test_read_response_body_handles_multibyte_characters
          # UTF-8 multibyte character: € is 3 bytes (E2 82 AC)
          response = FakeResponseStream.new(['Hello', ' €', '50'])
          body = @client.send(:read_response_body, response, 10)
          
          # Should get "Hello €5" (Hello=5, space=1, €=3, 5=1 = 10 bytes total)
          assert_equal 10, body.bytesize
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_stops_reading_after_limit
          chunks = ['A' * 100, 'B' * 100, 'C' * 100]
          response = FakeResponseStream.new(chunks)
          body = @client.send(:read_response_body, response, 50)
          
          assert_equal 50, body.bytesize
          assert_equal 'A' * 50, body
        end

        def test_read_response_body_uses_binary_encoding
          response = FakeResponseStream.new(['test'])
          body = @client.send(:read_response_body, response, 0)
          
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_handles_empty_response
          response = FakeResponseStream.new([])
          body = @client.send(:read_response_body, response, 0)
          
          assert_equal '', body
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_respects_byte_boundaries_with_limit
          # Test that max_bytes is respected at byte level, not character level
          response = FakeResponseStream.new(['ABC', 'DEF', 'GHI'])
          body = @client.send(:read_response_body, response, 5)
          
          assert_equal 5, body.bytesize
          assert_equal 'ABCDE', body
        end
      end
    end
  end
end
