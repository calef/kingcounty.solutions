# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require 'test_helper'
require 'mayhem/organizations/feed_updater'

class OrganizationProcessorTest < Minitest::Test
  class StubFeedFinder
    attr_reader :calls

    def initialize(responses = {})
      @responses = responses
      @calls = []
    end

    def find(url)
      @calls << url
      response = @responses[url]
      return unless response

      wrap_response(response)
    end

    private

    def wrap_response(response)
      return response if response.respond_to?(:any?)

      Mayhem::FeedDiscovery::FeedResult.new(response, nil)
    end
  end

  def setup
    @org_dir = Dir.mktmpdir('orgs')
  end

  def teardown
    FileUtils.remove_entry(@org_dir)
  end

  def test_updates_front_matter_when_feed_found
    write_org('example-org', website: 'https://example.org')
    finder = StubFeedFinder.new('https://example.org' => 'https://example.org/feed')

    processor = Mayhem::Organizations::FeedUpdater.new(
      org_dir: @org_dir,
      targets: [],
      limit: nil,
      dry_run: false,
      feed_finder: finder
    )

    result = processor.run

    assert_equal 1, result[:processed]
    assert_equal [['example-org.md', 'https://example.org/feed']], result[:updated]
    assert_empty result[:skipped]

    data = File.read(File.join(@org_dir, 'example-org.md'))

    assert_includes data, 'news_rss_url: https://example.org/feed'
  end

  def test_respects_targets_and_dry_run
    write_org('alpha', website: 'https://alpha.test')
    write_org('beta', website: 'https://beta.test')
    finder = StubFeedFinder.new('https://beta.test' => nil)

    processor = Mayhem::Organizations::FeedUpdater.new(
      org_dir: @org_dir,
      targets: ['beta'],
      limit: nil,
      dry_run: true,
      feed_finder: finder
    )

    result = processor.run

    assert_equal ['https://beta.test'], finder.calls
    assert_equal 1, result[:processed]
    assert_equal ['beta.md'], result[:skipped]

    data = File.read(File.join(@org_dir, 'beta.md'))

    refute_includes data, 'news_rss_url'
  end

  private

  def write_org(slug, website:, extra: {}, body: 'Body text')
    path = File.join(@org_dir, "#{slug}.md")
    data = { 'title' => slug.capitalize, 'website' => website }.merge(extra)
    front_matter = data.map { |key, value| "#{key}: #{value}" }.join("\n")

    File.write(
      path,
      <<~MARKDOWN
        ---
        #{front_matter}
        ---
        #{body}
      MARKDOWN
    )
    path
  end
end
