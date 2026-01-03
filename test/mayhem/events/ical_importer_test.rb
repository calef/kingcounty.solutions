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
    events = Mayhem::Models::Event.all.to_a
    assert_equal 1, events.count
    event = events.first

    assert_equal '_events/2024-02-12-test-event.md', event.id
    assert_equal 'Test Event', event.title
    assert_equal 'Test Organization', event.organization_title
    assert_equal '2024-02-12T18:00:00+00:00', event.start_date
    assert_equal '2024-02-12T20:00:00+00:00', event.end_date
    assert_equal 'Community Hall', event.location
    assert_equal 'https://example.org/events/test', event.source_url
    assert_equal '<p>Article body</p>', event.feed_content
    refute_includes event.feed_content, '<script'
    assert_includes event.feed_content, 'Article body'
    assert event.feed_content_checksum
    assert_nil event.original_source_html
  end

  def test_respects_locked_flag
    locked_record = Mayhem::Models::Event.create!(
      {
        'title' => 'Locked Event',
        'organization_title' => 'Locked Org',
        'start_date' => '2024-02-12T18:00:00+00:00',
        'end_date' => '2024-02-12T20:00:00+00:00',
        'location' => 'Anywhere',
        'source_url' => 'https://example.org/events/test',
        'feed_content' => '<p>Locked</p>',
        'locked' => true,
        'slug' => '2024-02-12-test-event'
      },
      body: 'Locked body'
    )
    locked_body = locked_record.body.dup
    @importer.run
    assert_equal 1, Mayhem::Models::Event.all.count
    assert_equal locked_body.strip, Mayhem::Models::Event.find(locked_record.id).body.strip
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
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    events = Mayhem::Models::Event.all.to_a
    assert_equal 1, events.count
    assert_equal canonical, events.first.source_url
  end

  def test_skips_past_events
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY_WITH_PAST_EVENT, content_type: 'text/calendar' },
      'https://example.org/events/test' => { body: HTML_BODY, content_type: 'text/html' },
      'https://example.org/events/old' => { body: HTML_BODY, content_type: 'text/html' }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    titles = Mayhem::Models::Event.all.map(&:title)
    assert_equal 1, titles.count
    assert_includes titles, 'Future Event'
    refute_includes titles, 'Old Event'
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
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => {
        body: HTML_BODY,
        content_type: 'text/html',
        final_url: canonical
      }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    events = Mayhem::Models::Event.all.to_a
    assert_equal 1, events.count
    assert_equal existing_record.id, events.first.id
  end

  def test_ignores_far_future_events
    @http = StubHttpClient.new(
      'https://example.org/events.ics' => { body: ICS_BODY_FAR_FUTURE, content_type: 'text/calendar' },
      'https://example.org/events/near' => { body: NEAR_HTML_BODY, content_type: 'text/html' },
      'https://example.org/events/far' => { body: HTML_BODY, content_type: 'text/html' }
    )
    @importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    @importer.run
    titles = Mayhem::Models::Event.all.map(&:title)
    assert_equal 1, titles.count
    assert_includes titles, 'Near Future Event'
    refute_includes titles, 'Too Far Event'
  end
end
