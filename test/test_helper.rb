# frozen_string_literal: true

require 'simplecov'
require_relative '../script/warning_filter'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'
  add_filter '/_site/'
end

require 'bundler/setup'
require 'minitest/autorun'

# Load default gems so tests can use the same environment as the site build.
Bundler.require(:default)
