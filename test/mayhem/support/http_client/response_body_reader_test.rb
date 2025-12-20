# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require_relative '../../../../lib/mayhem/support/http_client'
require_relative 'test_helpers'

module Mayhem
  module Support
    class HttpClient
      class ResponseBodyReaderTest < Minitest::Test
        include HttpClientTestHelpers

        def test_read_response_body_returns_full_body_when_max_bytes_is_zero
          response = HttpClientTestHelpers::FakeResponseStream.new(['Hello', ' ', 'World'])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 0)

          assert_equal 'Hello World', body
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_limits_to_max_bytes
          response = HttpClientTestHelpers::FakeResponseStream.new(['Hello', ' ', 'World'])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 7)

          assert_equal 'Hello W', body
          assert_equal 7, body.bytesize
        end

        def test_read_response_body_handles_multibyte_characters
          # UTF-8 multibyte character: € is 3 bytes (E2 82 AC)
          response = HttpClientTestHelpers::FakeResponseStream.new(['Hello', ' €', '50'])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 10)

          # Should get "Hello €5" (Hello=5, space=1, €=3, 5=1 = 10 bytes total)
          assert_equal 10, body.bytesize
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_stops_reading_after_limit
          chunks = ['A' * 100, 'B' * 100, 'C' * 100]
          response = HttpClientTestHelpers::FakeResponseStream.new(chunks)
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 50)

          assert_equal 50, body.bytesize
          assert_equal 'A' * 50, body
        end

        def test_read_response_body_uses_binary_encoding
          response = HttpClientTestHelpers::FakeResponseStream.new(['test'])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 0)

          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_handles_empty_response
          response = HttpClientTestHelpers::FakeResponseStream.new([])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 0)

          assert_equal '', body
          assert_equal Encoding::BINARY, body.encoding
        end

        def test_read_response_body_respects_byte_boundaries_with_limit
          # Test that max_bytes is respected at byte level, not character level
          response = HttpClientTestHelpers::FakeResponseStream.new(['ABC', 'DEF', 'GHI'])
          body = Mayhem::Support::HttpClient::ResponseBodyReader.read(response, 5)

          assert_equal 5, body.bytesize
          assert_equal 'ABCDE', body
        end
      end
    end
  end
end
