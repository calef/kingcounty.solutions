# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/robots_txt'

class RobotsTxtModelTest < Minitest::Test
  def setup
    @repo = FMRepo::TestHelpers.with_temp_repo(role: :robots_txts)
  end

  def teardown
    @repo&.cleanup
  end

  def test_slug_uses_domain
    record = Mayhem::Models::RobotsTxt.create!(
      { 'url' => 'https://example.com/robots.txt' },
      body: 'User-agent: *'
    )

    assert_equal '_robots_txts/example-com.md', record.id
  end

  def test_slug_includes_port_when_nonstandard
    record = Mayhem::Models::RobotsTxt.create!(
      { 'url' => 'https://example.com:8080/robots.txt' },
      body: ''
    )

    assert_equal '_robots_txts/example-com-8080.md', record.id
  end

  def test_handles_invalid_url
    record = Mayhem::Models::RobotsTxt.create!({ 'url' => '::not-a-url' }, body: '')

    assert_equal '_robots_txts/not-a-url.md', record.id
  end
end
