# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'simplecov'
require_relative '../script/warning_filter'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'
  add_filter '/_site/'
end

# reduce noisy logs during tests
ENV['LOG_LEVEL'] ||= 'ERROR'
require 'bundler/setup'
require 'minitest/autorun'

# Load default gems so tests can use the same environment as the site build.
Bundler.require(:default, :test)

# Configure VCR to record HTTP interactions for tests
require 'vcr'
VCR.configure do |c|
  c.cassette_library_dir = 'test/vcr_cassettes'
  c.hook_into :webmock
  c.configure_rspec_metadata! if defined?(RSpec) && c.respond_to?(:configure_rspec_metadata!)
  c.allow_http_connections_when_no_cassette = true
end
