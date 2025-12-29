# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/logging'
require 'mayhem/support/http_status_resolver'

class SupportHttpStatusResolverTest < Minitest::Test
  def setup
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
  end

  def test_invalid_scheme_returns_error
    resolver = build_resolver

    assert_equal :error, resolver.call('ftp://example.com/file')
  end

  def test_malformed_url_returns_error
    resolver = build_resolver

    assert_equal :error, resolver.call('not-a-url')
  end

  def test_successful_http_status_returns_success
    resolver = build_resolver(http_client: stub_client(status: 200))

    assert_equal :success, resolver.call('https://example.com')
  end

  def test_not_found_status_returns_not_found
    resolver = build_resolver(http_client: stub_client(status: 404))

    assert_equal :not_found, resolver.call('https://example.com')
  end

  def test_error_status_returns_error
    resolver = build_resolver(http_client: stub_client(status: 500))

    assert_equal :error, resolver.call('https://example.com')
  end

  def test_http_client_exception_results_in_error
    resolver = build_resolver(http_client: stub_client(error: StandardError.new('boom')))

    assert_equal :error, resolver.call('https://example.com')
  end

  private

  def build_resolver(**kwargs)
    Mayhem::Support::HttpStatusResolver.new(**kwargs
    )
  end

  def stub_client(status: nil, error: nil)
    Class.new do
      def initialize(status, error)
        @status = status
        @error = error
      end

      def response_for(_url, accept:)
        raise @error if @error
        return nil unless @status

        { status: @status, final_url: 'https://example.com' }
      end
    end.new(status, error)
  end
end
