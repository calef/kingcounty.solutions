# frozen_string_literal: true

require_relative 'test_helper'

class RuboCopComplianceTest < Minitest::Test
  def test_rubocop_passes
    command = ['bundle', 'exec', 'rubocop']
    # Run RuboCop with Bundler outside the current execution context to avoid nesting.
    result = Bundler.with_unbundled_env { system(*command) }

    assert result, "RuboCop found offenses; run #{command.join(' ')} locally."
  end
end
