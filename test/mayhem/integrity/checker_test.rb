# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/mayhem/integrity/checker'

class IntegrityCheckerTest < Minitest::Test
  def test_run_changes_to_project_root_and_passes_args_to_runner
    checker = Mayhem::Integrity::Checker.new
    calls = []

    Dir.stub(:chdir, ->(path, &block) { calls << path; block.call }) do
      checker.stub(:run_build, -> { calls << :run_build; true }) do
        checker.stub(:run_tests, ->(args) { calls << [:run_tests, args]; true }) do
          checker.run(%w[--seed 123])
        end
      end
    end

    assert_equal checker.send(:project_root), calls[0]
    assert_equal :run_build, calls[1]
    assert_equal [:run_tests, %w[--seed 123]], calls[2]
  end

end
