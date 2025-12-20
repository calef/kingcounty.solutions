# frozen_string_literal: true

require_relative '../test_helper'

# Load the CLI module from bin/mayhem
load File.expand_path('../../bin/mayhem', __dir__)

class MayhemCLITest < Minitest::Test
  def test_run_ingest_calls_check_integrity_at_end
    # Track which methods are called and in what order
    calls = []

    Mayhem::CLI.stub(:run_import_content, ->(_args) { calls << :run_import_content }) do
      Mayhem::CLI.stub(:run_summarize, ->(_args) { calls << :run_summarize }) do
        Mayhem::CLI.stub(:run_extract_events, ->(_args) { calls << :run_extract_events }) do
          Mayhem::CLI.stub(:run_extract_images, ->(_args) { calls << :run_extract_images }) do
            Mayhem::CLI.stub(:run_expire, ->(_args) { calls << :run_expire }) do
              Mayhem::CLI.stub(:run_check_integrity, ->(_args) { calls << :run_check_integrity }) do
                Mayhem::CLI.run_ingest([])
              end
            end
          end
        end
      end
    end

    # Verify all methods were called
    assert_includes calls, :run_import_content
    assert_includes calls, :run_summarize
    assert_includes calls, :run_extract_events
    assert_includes calls, :run_extract_images
    assert_includes calls, :run_expire
    assert_includes calls, :run_check_integrity

    # Verify run_check_integrity is called after run_expire (at the end)
    expire_index = calls.index(:run_expire)
    integrity_index = calls.index(:run_check_integrity)
    assert integrity_index > expire_index, 'check_integrity should be called after expire'
    assert_equal calls.last, :run_check_integrity, 'check_integrity should be the last call'
  end
end
