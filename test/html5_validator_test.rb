# frozen_string_literal: true

require 'pathname'
require 'test_helper'
require 'html5_validator'
require_relative 'support/site_build_helper'

class Html5ValidatorTest < Minitest::Test
  def setup
    skip 'Set RUN_EXPENSIVE_TESTS to a truthy value to run expensive validation suites' unless expensive_tests_enabled?
    SiteBuildHelper.ensure_site_built
    @validator = build_validator
  end

  def test_generated_html_complies_with_html5_validator
    skip 'html5_validator gem is not available' unless @validator

    html_files = Dir.glob(File.join(SiteBuildHelper.destination, '**', '*.html'))

    refute_empty html_files, 'Expected Jekyll build to produce HTML files'

    html_files.each do |path|
      errors = validate_path(path)
      next if errors.empty?

      assert_empty errors, html5_validator_error_message(path, errors)
    end
  end

  private

  def build_validator
    Html5Validator::Validator.new
  rescue StandardError => e
    warn "html5_validator unavailable: #{e.class}: #{e.message}"
    nil
  end

  def validate_path(path)
    @validator.validate_text(File.read(path))
    @validator.errors || []
  rescue RestClient::Exception, Errno::ECONNREFUSED, SocketError, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
         Errno::ETIMEDOUT => e
    skip "html5_validator service unreachable: #{e.class}: #{e.message}"
  rescue StandardError => e
    flunk "html5_validator failed for #{relative_path(path)}: #{e.class}: #{e.message}"
  end

  def html5_validator_error_message(path, errors)
    highlighted = errors.first(3).map do |err|
      line_info = err['lastLine'] && err['lastColumn'] ? " (line #{err['lastLine']}, col #{err['lastColumn']})" : ''
      "#{err['message']}#{line_info}"
    end

    <<~MSG
      html5_validator reported issues for #{relative_path(path)}:
      - #{highlighted.join("\n- ")}
    MSG
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(SiteBuildHelper.destination)).to_s
  end

  def expensive_tests_enabled?
    ENV['RUN_EXPENSIVE_TESTS'].to_s.strip.match?(/\A(?:1|t|true|yes|y)\z/i)
  end
end
