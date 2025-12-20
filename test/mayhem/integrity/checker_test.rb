# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/mayhem/integrity/checker'

class IntegrityCheckerTest < Minitest::Test
  def test_run_changes_to_project_root_and_passes_args_to_runner
    checker = Mayhem::Integrity::Checker.new
    calls = []

    Dir.stub(:chdir, ->(path, &block) { calls << path; block.call }) do
      checker.stub(:run_command, ->(path, args) { calls << [path, args] }) do
        checker.run(%w[--seed 123])
      end
    end

    assert_equal checker.send(:project_root), calls[0]
    assert_equal [Mayhem::Integrity::Checker::RUNNER_PATH, %w[--seed 123]], calls[1]
  end

  def test_run_command_invokes_bundle_exec_ruby_runner
    checker = Mayhem::Integrity::Checker.new
    commands = []

    Bundler.stub(:with_unbundled_env, ->(&block) { commands << :with_unbundled_env; block.call }) do
      checker.stub(:system, ->(*args) { commands << args; true }) do
        assert checker.send(:run_command, '/tmp/runner.rb', %w[--name foo])
      end
    end

    assert_equal :with_unbundled_env, commands.first
    assert_equal ['bundle', 'exec', 'ruby', '/tmp/runner.rb', '--name', 'foo'], commands.last
  end
end
