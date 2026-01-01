# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/website'
require 'mayhem/robots/refresh'

class RobotsRefreshTest < Minitest::Test
  class FakeHttpClient
    def initialize(responses = {})
      @responses = responses
    end

    def fetch(url, accept:)
      @responses[url] || { body: '', content_type: 'text/plain', final_url: url }
    end
  end

  def setup
    @web_repo = FMRepo::TestHelpers.with_temp_repo(role: :websites)
    @robots_repo = FMRepo::TestHelpers.with_temp_repo(role: :robots_txts)
    @website = Mayhem::Models::Website.create!(
      {
        'title' => 'Example Site',
        'homepage_url' => 'https://example.com'
      },
      body: ''
    )
  end

  def teardown
    @web_repo&.cleanup
    @robots_repo&.cleanup
  end

  def test_refresh_stores_new_robots_txt
    client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: 'User-agent: *',
        final_url: 'https://example.com/robots.txt'
      }
    )
    refresh = Mayhem::Robots::Refresh.new(http_client: client)

    result = refresh.refresh(@website)

    record = Mayhem::Models::RobotsTxt.find_by(website_id: @website.id)
    assert_equal 'https://example.com/robots.txt', result
    assert_equal 'https://example.com/robots.txt', record['url']
    assert_equal 'User-agent: *', record.body.strip
  end

  def test_refresh_updates_existing_record
    Mayhem::Models::RobotsTxt.create!(
      {
        'url' => 'https://example.com/robots.txt',
        'website_id' => @website.id,
        'last_modified' => Time.now.utc.iso8601
      },
      body: 'old'
    )

    client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: 'new',
        final_url: 'https://example.com/robots.txt'
      }
    )
    refresh = Mayhem::Robots::Refresh.new(http_client: client)

    refresh.refresh(@website)

    record = Mayhem::Models::RobotsTxt.find_by(url: 'https://example.com/robots.txt', website_id: @website.id)
    assert_equal 'new', record.body.strip
  end

  def test_refresh_updates_website_when_redirects
    client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: '# robots',
        final_url: 'https://example.com/robots-final.txt'
      }
    )
    refresh = Mayhem::Robots::Refresh.new(http_client: client)

    refresh.refresh(@website)

    record = Mayhem::Models::RobotsTxt.find_by(url: 'https://example.com/robots-final.txt',
                                               website_id: @website.id)
    assert_equal '# robots', record.body.strip
  end

  def test_refresh_returns_nil_without_url
    website = Mayhem::Models::Website.create!({ 'title' => 'No URL' }, body: '')
    refresh = Mayhem::Robots::Refresh.new(http_client: FakeHttpClient.new)

    assert_nil refresh.refresh(website)
  end
end
