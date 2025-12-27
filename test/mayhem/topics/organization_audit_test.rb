# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/mayhem/topics/organization_audit'

class OrganizationAuditTest < Minitest::Test
  FakeClient = Struct.new(:response) do
    def chat(*)
      response
    end
  end

  def setup
    client = FakeClient.new
    @audit = Mayhem::Topics::OrganizationAudit.new(
      client: client,
      logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    )
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
