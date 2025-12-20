# frozen_string_literal: true

require 'parallel_tests'

desc 'Run the MiniTest suite using parallel_tests'
task :test do
  command = [Gem.bin_path('parallel_tests', 'parallel_test'), 'test']
  abort('parallel_test failed') unless system(*command)
end

task default: :test
