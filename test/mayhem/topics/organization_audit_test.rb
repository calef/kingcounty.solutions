# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../../../lib/mayhem/topics/organization_audit'

class OrganizationAuditTest < Minitest::Test
  FakeClient = Struct.new(:response) do
    def chat(*)
      response
    end
  end

  def setup
    @tmp_dirs = Array.new(3) { Dir.mktmpdir }
    client = FakeClient.new
    @audit = Mayhem::Topics::OrganizationAudit.new(
      client: client,
      org_dir: @tmp_dirs[0],
      topic_dir: @tmp_dirs[1],
      posts_dir: @tmp_dirs[2],
      logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    )
  end

  def teardown
    @tmp_dirs.each { |d| FileUtils.remove_entry(d) }
  end

  def test_normalize_response_strips_triple_backtick_json
    response = <<~RESPONSE
      ```json
      { "topics_true": ["Health"] }
      ```
    RESPONSE

    normalized = @audit.send(:normalize_response, response)

    assert_equal '{ "topics_true": ["Health"] }', normalized
  end

  def test_normalize_response_extracts_json_from_plain_text
    response = "Result:\n{ \"topics_true\": [\"Food\"] }\nThanks!"

    normalized = @audit.send(:normalize_response, response)

    assert_equal '{ "topics_true": ["Food"] }', normalized
  end

  def test_normalize_response_returns_trimmed_content_when_no_json
    response = "  just a simple message  "

    normalized = @audit.send(:normalize_response, response)

    assert_equal 'just a simple message', normalized
  end
end
