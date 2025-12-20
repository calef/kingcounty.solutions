# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'
require_relative '../../../../lib/mayhem/support/http_client'
require_relative 'test_helpers'

module Mayhem
  module Support
    class HttpClient
      class OperationDelayManagerTest < Minitest::Test
        include HttpClientTestHelpers

        def setup
          @logger = HttpClientTestHelpers::FakeLogger.new
        end

        def test_normalize_operation_host_delays_with_valid_config
          client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            host_operation_delays: {
              'canonical_head' => {
                'example.com' => 1.5,
                'test.com' => 2.0
              },
              'content_fetch' => {
                'api.example.com' => 0.5
              }
            }
          )
          
          normalized = client.send(:normalize_operation_host_delays, {
            'canonical_head' => {
              'example.com' => 1.5,
              'test.com' => 2.0
            }
          })
          
          assert_equal 1.5, normalized['canonical_head']['example.com']
          assert_equal 2.0, normalized['canonical_head']['test.com']
        end

        def test_normalize_operation_host_delays_ignores_invalid_values
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          normalized = client.send(:normalize_operation_host_delays, {
            'op1' => {
              'valid.com' => 1.0,
              'zero.com' => 0,
              'negative.com' => -1.0,
              '' => 1.0
            }
          })
          
          assert_equal 1.0, normalized['op1']['valid.com']
          assert_nil normalized['op1']['zero.com']
          assert_nil normalized['op1']['negative.com']
          assert_nil normalized['op1']['']
        end

        def test_normalize_operation_host_delays_handles_empty_config
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          normalized = client.send(:normalize_operation_host_delays, {})
          assert_equal({}, normalized)
          
          normalized = client.send(:normalize_operation_host_delays, nil)
          assert_equal({}, normalized)
        end

        def test_normalize_operation_host_delays_lowercases_host_names
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          normalized = client.send(:normalize_operation_host_delays, {
            'op1' => {
              'Example.COM' => 1.0,
              'TEST.net' => 2.0
            }
          })
          
          assert_equal 1.0, normalized['op1']['example.com']
          assert_equal 2.0, normalized['op1']['test.net']
        end

        def test_normalize_operation_host_delays_converts_to_string_keys
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          normalized = client.send(:normalize_operation_host_delays, {
            :canonical_head => {
              'example.com' => 1.5
            }
          })
          
          assert_equal 1.5, normalized['canonical_head']['example.com']
        end

        def test_apply_operation_delay_without_configured_delay
          client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            host_operation_delays: {}
          )
          
          # Should not sleep when no delay is configured
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          client.send(:apply_operation_delay, 'test_op', URI('https://example.com'))
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          
          # Should be nearly instant (< 0.1 seconds)
          assert_operator (end_time - start_time), :<, 0.1
        end

        def test_apply_operation_delay_with_configured_delay
          client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            host_operation_delays: {
              'test_op' => {
                'example.com' => 0.05
              }
            }
          )
          
          # First call should not delay (no previous request)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          client.send(:apply_operation_delay, 'test_op', URI('https://example.com'))
          first_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          
          # Second call should delay
          client.send(:apply_operation_delay, 'test_op', URI('https://example.com'))
          second_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          
          # Second call should take at least the delay time
          second_duration = second_end - first_end
          assert_operator second_duration, :>=, 0.04 # Allow small margin
        end

        def test_apply_operation_delay_is_host_specific
          client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            host_operation_delays: {
              'test_op' => {
                'example.com' => 0.1,
                'other.com' => 0.1
              }
            }
          )
          
          # Request to example.com
          client.send(:apply_operation_delay, 'test_op', URI('https://example.com'))
          
          # Immediate request to other.com should not be delayed (different host)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          client.send(:apply_operation_delay, 'test_op', URI('https://other.com'))
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          
          assert_operator (end_time - start_time), :<, 0.05
        end

        def test_apply_operation_delay_handles_nil_operation
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          # Should not raise error
          assert_silent do
            client.send(:apply_operation_delay, nil, URI('https://example.com'))
          end
        end

        def test_apply_operation_delay_handles_nil_uri
          client = Mayhem::Support::HttpClient.new(logger: @logger, delay: 0)
          
          # Should not raise error
          assert_silent do
            client.send(:apply_operation_delay, 'test_op', nil)
          end
        end

        def test_default_operation_host_delays_includes_pubmed
          # Temporarily set the environment variable
          original_value = ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY']
          ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = '2.5'
          
          client = Mayhem::Support::HttpClient.new(
            logger: @logger,
            delay: 0,
            host_operation_delays: nil # Use default
          )
          
          defaults = client.send(:default_operation_host_delays)
          assert_equal 2.5, defaults.dig('canonical_head', 'pubmed.ncbi.nlm.nih.gov')
        ensure
          # Restore original value
          if original_value
            ENV['RSS_PUBMED_CANONICAL_HEAD_DELAY'] = original_value
          else
            ENV.delete('RSS_PUBMED_CANONICAL_HEAD_DELAY')
          end
        end
      end
    end
  end
end
