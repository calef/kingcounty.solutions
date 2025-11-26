# frozen_string_literal: true

task_name = :test

begin
  require 'parallel_tests'
rescue LoadError
  require 'rake/testtask'
end

if defined?(ParallelTests)
  desc 'Run the MiniTest suite using parallel_tests'
  task task_name do
    command = [Gem.bin_path('parallel_tests', 'parallel_test'), 'test']
    abort('parallel_test failed') unless system(*command)
  end
else
  Rake::TestTask.new(task_name) do |t|
    t.libs << 'test'
    t.pattern = 'test/**/*_test.rb'
  end
end

task default: task_name
