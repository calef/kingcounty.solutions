# frozen_string_literal: true

require_relative 'test_helper'

Dir.glob(File.expand_path('tests/**/*_test.rb', __dir__)).sort.each do |file|
  require file
end
