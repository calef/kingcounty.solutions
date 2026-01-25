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

  # --- Threading Edge Case Tests (Issue 5.1) ---

  def test_concurrent_organization_imports_are_thread_safe
    # Create multiple organizations with unique events
    (2..5).each do |i|
      Mayhem::Models::Organization.create!(
        {
          'title' => "Organization #{i}",
          'website_url' => "https://org#{i}.example.org/",
          'events_ical_url' => "https://org#{i}.example.org/events.ics"
        },
        body: ''
      )
    end

    # Create unique ICS content for each organization
    responses = {
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => { body: HTML_BODY, content_type: 'text/html' }
    }

    (2..5).each do |i|
      ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:org#{i}-event
        SUMMARY:Event from Org #{i}
        DTSTART:20240212T180000Z
        DTEND:20240212T200000Z
        LOCATION:Hall #{i}
        DESCRIPTION:Description #{i}
        URL:https://org#{i}.example.org/events/event#{i}
        END:VEVENT
        END:VCALENDAR
      ICS
      responses["https://org#{i}.example.org/events.ics"] = { body: ics, content_type: 'text/calendar' }
      responses["https://org#{i}.example.org/events/event#{i}"] = { body: HTML_BODY, content_type: 'text/html' }
    end

    thread_safe_http = ThreadSafeStubHttpClient.new(responses)
    importer = Mayhem::Events::IcalImporter.new(
      http_client: thread_safe_http,
      workers: 4,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    importer.run

    events = Mayhem::Models::Event.all.to_a
    # Should have 5 events total (1 from original setup + 4 from new orgs)
    assert_equal 5, events.count, 'All organizations should create events without race conditions'

    titles = events.map(&:title).sort
    assert_includes titles, 'Test Event'
    assert_includes titles, 'Event from Org 2'
    assert_includes titles, 'Event from Org 3'
    assert_includes titles, 'Event from Org 4'
    assert_includes titles, 'Event from Org 5'
  end

  def test_stats_collection_is_thread_safe_under_contention
    # Create many organizations to stress test stats collection
    org_count = 10
    (2..org_count).each do |i|
      Mayhem::Models::Organization.create!(
        {
          'title' => "Stats Org #{i}",
          'website_url' => "https://stats#{i}.example.org/",
          'events_ical_url' => "https://stats#{i}.example.org/events.ics"
        },
        body: ''
      )
    end

    responses = {
      'https://example.org/events.ics' => { body: ICS_BODY, content_type: 'text/calendar' },
      'https://example.org/events/test' => { body: HTML_BODY, content_type: 'text/html' }
    }

    # Half of the organizations will have valid events, half will have missing URLs
    (2..org_count).each do |i|
      if i.even?
        # Valid event
        ics = <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          BEGIN:VEVENT
          UID:stats#{i}-event
          SUMMARY:Stats Event #{i}
          DTSTART:20240212T180000Z
          URL:https://stats#{i}.example.org/events/event#{i}
          END:VEVENT
          END:VCALENDAR
        ICS
        responses["https://stats#{i}.example.org/events.ics"] = { body: ics, content_type: 'text/calendar' }
        responses["https://stats#{i}.example.org/events/event#{i}"] = { body: HTML_BODY, content_type: 'text/html' }
      else
        # Event without URL (will be skipped)
        ics = <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          BEGIN:VEVENT
          UID:stats#{i}-event
          SUMMARY:No URL Event #{i}
          DTSTART:20240212T180000Z
          END:VEVENT
          END:VCALENDAR
        ICS
        responses["https://stats#{i}.example.org/events.ics"] = { body: ics, content_type: 'text/calendar' }
      end
    end

    thread_safe_http = ThreadSafeStubHttpClient.new(responses)
    importer = Mayhem::Events::IcalImporter.new(
      http_client: thread_safe_http,
      workers: 6,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    # Should complete without deadlock or race condition in stats collection
    importer.run

    events = Mayhem::Models::Event.all.to_a
    # Original + 4 even-numbered orgs (2, 4, 6, 8) should have events
    assert_operator events.count, :>=, 5, 'Valid events should be created'
  end

  def test_normalized_link_warns_on_relative_url_without_base
    logger = Minitest::Mock.new
    logger.expect(:warn, nil, [/normalized_link: Cannot normalize relative URL without base URL/])

    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )
    importer.stub(:logger, logger) do
      result = importer.send(:normalized_link, '/relative/path', nil)

      assert_nil result
    end

    logger.verify
  end

  def test_normalized_link_allows_absolute_url_without_base
    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )
    result = importer.send(:normalized_link, 'https://example.org/path', nil)

    assert_equal 'https://example.org/path', result
  end

  def test_normalized_link_warns_on_protocol_relative_url_without_base
    logger = Minitest::Mock.new
    logger.expect(:warn, nil, [/normalized_link: Cannot normalize relative URL without base URL/])

    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )
    importer.stub(:logger, logger) do
      result = importer.send(:normalized_link, '//example.org/path', nil)

      assert_nil result
    end

    logger.verify
  end

  def test_normalized_link_handles_unusual_schemes
    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    # FTP scheme
    result = importer.send(:normalized_link, 'ftp://files.example.org/path', nil)
    assert_equal 'ftp://files.example.org/path', result

    # Mailto scheme
    result = importer.send(:normalized_link, 'mailto:info@example.org', nil)
    assert_equal 'mailto:info@example.org', result

    # Data URI scheme
    result = importer.send(:normalized_link, 'data:text/plain;base64,SGVsbG8=', nil)
    assert_equal 'data:text/plain;base64,SGVsbG8=', result
  end

  def test_normalized_link_handles_numeric_schemes
    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    # Scheme starting with a number (theoretical but valid per RFC)
    result = importer.send(:normalized_link, '3g2://example.org/path', nil)
    assert_equal '3g2://example.org/path', result
  end

  def test_normalized_link_handles_empty_and_whitespace
    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )

    # Empty string
    result = importer.send(:normalized_link, '', nil)
    assert_nil result

    # Whitespace only
    result = importer.send(:normalized_link, '   ', nil)
    assert_nil result

    # nil
    result = importer.send(:normalized_link, nil, nil)
    assert_nil result
  end

  def test_normalized_link_handles_malformed_urls
    logger = Minitest::Mock.new
    # Malformed URLs should be treated as relative since they lack a proper scheme
    logger.expect(:warn, nil, [/normalized_link: Cannot normalize relative URL without base URL/])

    importer = Mayhem::Events::IcalImporter.new(
      http_client: @http,
      time_source: -> { Time.utc(2024, 1, 1) }
    )
    importer.stub(:logger, logger) do
      result = importer.send(:normalized_link, 'ht tp://broken.com', nil)

      assert_nil result
    end

    logger.verify
  end

  # Thread-safe HTTP client for concurrent tests
  class ThreadSafeStubHttpClient
    def initialize(responses)
      @responses = responses
      @mutex = Mutex.new
      @calls = []
    end

    def fetch(url, accept:)
      @mutex.synchronize { @calls << { url: url, accept: accept } }

      # Simulate network latency to increase chance of race conditions
      sleep(rand * 0.01)

      response = @responses[url]
      raise Seldon::Support::HttpClient::HttpError, "Missing stub response for #{url}" unless response

      {
        body: response[:body],
        content_type: response[:content_type],
        final_url: response.fetch(:final_url, url)
      }
    end

    attr_reader :calls
  end
end
