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
# default to a development-specific FMRepo environment unless explicitly overridden
fmrepo_env = ENV['FMREPO_ENV'] || ENV['JEKYLL_ENV'] || 'development'
ENV['FMREPO_ENV'] = fmrepo_env
require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/mock'

# Load default gems so tests can use the same environment as the site build.
Bundler.require(:default, :test)

require 'fmrepo'
FMRepo.environment = fmrepo_env
FMRepo.configure do |config|
  config.repositories = {}
  config.load_yaml('.fmrepo.yml')
end
require 'fmrepo/test_helpers'
Minitest.after_run { FMRepo.repository_registry.cleanup_temp_dirs }
