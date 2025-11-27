# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/http_client'
require_relative '../../lib/mayhem/logging'

class HttpClientSmokeTest < Minitest::Test
  def test_http_client_instantiation
    client = Mayhem::Support::HttpClient.new(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))

    assert_respond_to client, :fetch
  end
end
