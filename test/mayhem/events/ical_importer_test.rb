# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/mayhem/events/ical_importer'
require 'mayhem/models/event'
require 'mayhem/models/organization'

class IcalImporterTest < Minitest::Test
  ICS_BODY = <<~ICS
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:1
    SUMMARY:Test Event
    DTSTART:20240212T180000Z
    DTEND:20240212T200000Z
    LOCATION:Community Hall
    DESCRIPTION:Event overview
    URL:https://example.org/events/test
    END:VEVENT
    END:VCALENDAR
  ICS

  ICS_BODY_WITH_PAST_EVENT = <<~ICS
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:1
    SUMMARY:Future Event
    DTSTART:20240212T180000Z
    DTEND:20240212T200000Z
    LOCATION:Community Hall
    DESCRIPTION:Event overview
    URL:https://example.org/events/test
    END:VEVENT
    BEGIN:VEVENT
    UID:2
    SUMMARY:Old Event
    DTSTART:20001012T180000Z
    DTEND:20001012T200000Z
    LOCATION:Old Hall
    DESCRIPTION:Old summary
    URL:https://example.org/events/old
    END:VEVENT
    END:VCALENDAR
  ICS

  ICS_BODY_FAR_FUTURE = <<~ICS
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:1
    SUMMARY:Near Future Event
    DTSTART:20240212T180000Z
    DTEND:20240212T200000Z
    LOCATION:Community Hall
    DESCRIPTION:Near summary
    URL:https://example.org/events/near
    END:VEVENT
    BEGIN:VEVENT
    UID:2
    SUMMARY:Too Far Event
    DTSTART:20240715T180000Z
    DTEND:20240715T200000Z
    LOCATION:Far Hall
    DESCRIPTION:Far summary
    URL:https://example.org/events/far
    END:VEVENT
    END:VCALENDAR
  ICS

  HTML_BODY = <<~HTML
    <html><body>
    <article class="article-body">
      <p>Article    body</p>
      <script>console.log('noise');</script>
      <div></div>
    </article>
    </body></html>
  HTML

  NEAR_HTML_BODY = <<~HTML
    <html><body>
    <article class="article-body"><p>Near content</p></article>
    </body></html>
  HTML

  class StubHttpClient
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def fetch(url, accept:)
      @calls << { url: url, accept: accept }
      response = @responses[url]
      raise "Missing stub response for #{url}" unless response

      {
        body: response[:body],
        content_type: response[:content_type],
        final_url: response.fetch(:final_url, url)
      }
    end
  end

  def setup
    @org_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :organizations)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @org_repo = Mayhem::Models::Organization.repo
    @events_repo = Mayhem::Models::Event.repo
    @org_dir = @org_repo.root.join(Mayhem::Models::Organization.collection_dir).to_s
    @events_dir = @events_repo.root.join('_events').to_s

    Mayhem::Models::Organization.create!(
      {
        'title' => 'Test Organization',
        'website_url' => 'https://example.org/',
        'events_ical_url' => 'https://example.org/events.ics'
      },
      body: ''
    )
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => { body: HTML_BODY, content_type: 'text/html' }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      events_dir: @events_dir,
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )
  end

  def teardown
    @org_repo_override.cleanup if @org_repo_override
    @event_repo_override.cleanup if @event_repo_override
  end

  def test_imports_single_event
    @importer.run
    files = Dir.glob(File.join(@events_dir, '*.md'))
    assert_equal 1, files.count

    assert_equal '2024-02-12-test-event.md', File.basename(files.first)

    content = File.read(files.first)

    assert_includes content, 'title: Test Event'
    assert_includes content, 'organization_title: Test Organization'
    assert_includes content, "start_date: '2024-02-12T18:00:00+00:00'"
    assert_includes content, "end_date: '2024-02-12T20:00:00+00:00'"
    assert_includes content, 'location: Community Hall'
    assert_includes content, 'source_url: https://example.org/events/test'
    assert_includes content, 'feed_content: "<p>Article body</p>"'
    assert_includes content, 'feed_content_checksum:'
    refute_includes content, 'original_content:'
    refute_includes content, '<script'
    assert_includes content, 'Article body'
  end

  def test_respects_locked_flag
    locked_record = Mayhem::Models::Event.create!(
      {
        'title' => 'Locked Event',
        'organization_title' => 'Locked Org',
        'start_date' => '2024-02-12T18:00:00+00:00',
        'end_date' => '2024-02-12T20:00:00+00:00',
        'location' => 'Anywhere',
        'source_url' => 'https://example.org/events/locked',
        'feed_content' => '<p>Locked</p>',
        'locked' => true,
        'slug' => '2024-02-12-test-event'
      },
      body: 'Locked body'
    )
    locked_path = locked_record.path.to_s

    frozen_content = File.read(locked_path)
    @importer.run

    files = Dir.glob(File.join(@events_dir, '*.md'))
    assert_equal 1, files.count
    assert_equal frozen_content, File.read(locked_path)
  end

  def test_uses_canonical_source_url
    canonical = 'https://example.org/events/test?utm=ical'
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => {
        body: HTML_BODY,
        content_type: 'text/html',
        final_url: canonical
      }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      events_dir: @events_dir,
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    files = Dir.glob(File.join(@events_dir, '*.md'))
    assert_equal 1, files.count

    content = File.read(files.first)
    assert_includes content, "source_url: #{canonical}"
  end

  def test_skips_past_events
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY_WITH_PAST_EVENT, content_type: 'text/calendar' },
      'https://example.org/events/test' => { body: HTML_BODY, content_type: 'text/html' },
      'https://example.org/events/old' => { body: HTML_BODY, content_type: 'text/html' }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      events_dir: @events_dir,
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    files = Dir.glob(File.join(@events_dir, '*.md'))
    assert_equal 1, files.count

    content = File.read(files.first)
    assert_includes content, 'title: Future Event'
    refute_includes content, 'title: Old Event'
  end

  def test_skips_duplicate_when_canonical_exists
    canonical = 'https://example.org/events/test?utm=existing'
    existing_record = Mayhem::Models::Event.create!(
      {
        'title' => 'Existing Event',
        'source_url' => canonical,
        'slug' => '2024-02-12-existing'
      },
      body: 'Existing body'
    )
    existing_path = existing_record.path.to_s

    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => {
        body: HTML_BODY,
        content_type: 'text/html',
        final_url: canonical
      }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      events_dir: @events_dir,
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    files = Dir.glob(File.join(@events_dir, '*.md')).sort
    assert_equal [existing_path], files
  end

  def test_ignores_far_future_events
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY_FAR_FUTURE, content_type: 'text/calendar' },
      'https://example.org/events/near' => { body: NEAR_HTML_BODY, content_type: 'text/html' },
      'https://example.org/events/far' => { body: HTML_BODY, content_type: 'text/html' }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      events_dir: @events_dir,
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    files = Dir.glob(File.join(@events_dir, '*.md'))
    assert_equal 1, files.count

    content = File.read(files.first)
    assert_includes content, 'title: Near Future Event'
    refute_includes content, 'title: Too Far Event'
  end
end
