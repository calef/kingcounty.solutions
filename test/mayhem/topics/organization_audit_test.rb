# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'
require 'mayhem/models/organization'
require 'mayhem/models/news'
require 'mayhem/models/topic'
require 'seldon'
require_relative '../../../lib/mayhem/topics/organization_audit'

class OrganizationAuditTest < Minitest::Test
  FakeClient = Struct.new(:response) do
    def chat(*)
      response
    end
  end

  class FakeLogger
    attr_reader :infos, :warns

    def initialize
      @infos = []
      @warns = []
    end

    def info(message)
      @infos << message
    end

    def warn(message)
      @warns << message
    end
  end

  def setup
    client = FakeClient.new
    @logger = FakeLogger.new
    Seldon::Logging.logger = @logger
    @audit = Mayhem::Topics::OrganizationAudit.new(
      client: client
    )
  end

  def teardown
    Seldon::Logging.reset_logger
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

  def test_load_recent_posts_sorts_and_limits
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new, max_posts: 2)
    with_org_repo do
      with_news_repo do
        org = create_org(title: 'Org', body: 'Org')
        post_old = Mayhem::Models::News.create!(
          {
            'title' => 'Old',
            'date' => '2023-01-01',
            'organization_title' => 'Org',
            'summarized' => true
          },
          body: 'old'
        )
        post_new = Mayhem::Models::News.create!(
          {
            'title' => 'New',
            'date' => '2024-01-01',
            'organization_title' => 'Org',
            'summarized' => true
          },
          body: 'new'
        )
        post_mid = Mayhem::Models::News.create!(
          {
            'title' => 'Mid',
            'date' => '2023-06-01',
            'organization_title' => 'Org',
            'summarized' => true
          },
          body: 'mid'
        )

        recent = audit.send(:load_recent_posts, org)

        assert_equal %w[New Mid], recent.map(&:title)
      end
    end
  end

  def test_build_prompt_includes_catalog_description_and_posts
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    with_org_repo do
      with_topic_repo do
        with_news_repo do
          create_topic(title: 'Food', body: '')
          create_topic(title: 'Health', body: 'Medical help.')
          create_topic(title: nil, body: 'Ignored')
          topics = Mayhem::Models::Topic.all.to_a
          org = create_org(
            title: 'Org A',
            topic_titles: ['Food'],
            summary: 'Summary',
            description: 'Description',
            body: 'Body text'
          )
          post = create_news(
            title: 'Update',
            date: '2024-01-01',
            organization_title: 'Org A',
            body: 'Some news for the org.'
          )

          prompt = audit.send(:build_prompt, org, topics, [post])

          assert_includes prompt, '- Food: No summary provided.'
          assert_includes prompt, '- Health: Medical help.'
          assert_includes prompt, 'Organization: Org A'
          assert_includes prompt, 'Existing topics: Food'
          assert_includes prompt, "Summary\n\nDescription\n\nBody text"
          assert_includes prompt, "Update (#{post.date}): Some news for the org."
        end
      end
    end
  end

  def test_build_prompt_includes_no_recent_posts_placeholder
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    with_org_repo do
      org = create_org(title: 'Org A')

      prompt = audit.send(:build_prompt, org, [], [])

      assert_includes prompt, 'No recent posts.'
    end
  end

  def test_filter_result_filters_unknown_titles
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    result = {
      'topics_true' => ['Food', 'Other'],
      'topics_false' => ['Housing'],
      'topics_unclear' => ['Food', 'Other'],
      'notes' => 'ok'
    }

    filtered = audit.send(:filter_result, result, ['Food', 'Housing'])

    assert_equal ['Food'], filtered['topics_true']
    assert_equal ['Housing'], filtered['topics_false']
    assert_equal ['Food'], filtered['topics_unclear']
    assert_equal 'ok', filtered['notes']
    assert_nil audit.send(:filter_result, nil, ['Food'])
  end

  def test_record_report_additions_and_removals
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    with_org_repo do
      org = create_org(title: 'Org A', topic_titles: ['Food', 'Housing'])
      result = {
        'topics_true' => ['Food', 'Health'],
        'topics_false' => ['Housing'],
        'topics_unclear' => ['Other'],
        'notes' => 'Check'
      }

      audit.send(:record_report, org, result)

      report = audit.instance_variable_get(:@report)
      assert_equal 1, report.length
      entry = report.first
      assert_equal 'Org A', entry[:org]
      assert_equal ['Health'], entry[:additions]
      assert_equal ['Housing'], entry[:removals]
      assert_equal ['Other'], entry[:unclear]
      assert_equal 'Check', entry[:notes]
    end
  end

  def test_apply_changes_updates_topics_and_saves
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new, apply: true)
    with_org_repo do
      org = create_org(title: 'Org A', topic_titles: ['Food', 'Housing'])
      result = {
        'topics_true' => ['Health'],
        'topics_false' => ['Food']
      }

      audit.send(:apply_changes, org, result)

      updated = Mayhem::Models::Organization.find(org.id)
      assert_equal ['Health', 'Housing'], updated.topic_titles
      assert_includes @logger.infos.first, "Updated #{org.id} topic_titles: Health, Housing"
    end
  end

  def test_apply_changes_skips_when_no_changes
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new, apply: true)
    with_org_repo do
      org = create_org(title: 'Org A', topic_titles: ['Food'])
      result = {
        'topics_true' => ['Food'],
        'topics_false' => []
      }

      audit.send(:apply_changes, org, result)

      updated = Mayhem::Models::Organization.find(org.id)
      assert_equal ['Food'], updated.topic_titles
      assert_empty @logger.infos
    end
  end

  def test_write_report_writes_json_when_output_set
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'report.json')
      audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new, output: output)
      report = [{ org: 'Org A', additions: ['Food'], removals: [], unclear: [], notes: nil }]
      audit.instance_variable_set(:@report, report)

      audit.send(:write_report)

      assert_equal JSON.pretty_generate(report), File.read(output)
      assert_includes @logger.infos.first, "Report written to #{output}"
    end
  end

  def test_write_report_prints_when_output_missing
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    called = false

    audit.stub(:print_report, -> { called = true }) do
      audit.send(:write_report)
    end

    assert called
  end

  def test_print_report_logs_entries
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    audit.instance_variable_set(
      :@report,
      [{
        org: 'Org A',
        additions: ['Food'],
        removals: [],
        unclear: ['Health'],
        notes: 'Check'
      }]
    )

    audit.send(:print_report)

    assert_includes @logger.infos, '== Org A =='
    assert_includes @logger.infos, 'Add: Food'
    assert_includes @logger.infos, 'Remove: (none)'
    assert_includes @logger.infos, 'Unclear: Health'
    assert_includes @logger.infos, 'Notes: Check'
  end

  def test_safe_parse_json_parses_valid_json
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)

    parsed = audit.send(:safe_parse_json, '{ "topics_true": ["Food"] }', 'Org A')

    assert_equal({ 'topics_true' => ['Food'] }, parsed)
  end

  def test_safe_parse_json_warns_on_invalid_json
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)

    parsed = audit.send(:safe_parse_json, 'not json', 'Org A')

    assert_nil parsed
    assert_includes @logger.warns.first, 'Non-JSON response for Org A'
  end

  def test_audit_org_parses_and_filters_response
    client = Class.new do
      attr_reader :last_parameters

      def initialize(response)
        @response = response
      end

      def chat(parameters:)
        @last_parameters = parameters
        @response
      end
    end
    response = {
      'choices' => [
        { 'message' => { 'content' => '{"topics_true":["Food","Other"],"topics_false":["Housing"],"topics_unclear":["Other"],"notes":"ok"}' } }
      ]
    }
    audit = Mayhem::Topics::OrganizationAudit.new(
      client: client.new(response),
      model: 'test-model'
    )
    with_org_repo do
      with_topic_repo do
        create_topic(title: 'Food', body: 'desc')
        create_topic(title: 'Housing', body: 'desc')
        topics = Mayhem::Models::Topic.all.to_a
        org = create_org(title: 'Org A', topic_titles: [])

        result = audit.send(:audit_org, org, topics, [])

        assert_equal ['Food'], result['topics_true']
        assert_equal ['Housing'], result['topics_false']
        assert_equal [], result['topics_unclear']
        assert_equal 'ok', result['notes']
        assert_equal 'test-model', audit.instance_variable_get(:@client).last_parameters[:model]
      end
    end
  end

  def test_process_org_skips_when_audit_returns_nil
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
    with_org_repo do
      with_news_repo do
        org = create_org(title: 'Org A')

        audit.stub(:audit_org, nil) do
          audit.send(:process_org, org, [])
        end

        assert_includes @logger.warns.first, 'Skipping Org A due to parse errors'
        assert_empty audit.instance_variable_get(:@report)
      end
    end
  end

  def test_process_org_records_and_applies_changes
    audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new, apply: true)
    with_org_repo do
      with_news_repo do
        org = create_org(title: 'Org A', topic_titles: ['Food'])
        result = {
          'topics_true' => ['Health'],
          'topics_false' => ['Food'],
          'topics_unclear' => []
        }

        audit.stub(:audit_org, result) do
          audit.send(:process_org, org, [])
        end

        report = audit.instance_variable_get(:@report)
        assert_equal 1, report.length
        updated = Mayhem::Models::Organization.find(org.id)
        assert_equal ['Health'], updated.topic_titles
      end
    end
  end

  def test_run_processes_all_orgs_and_writes_report
    with_org_repo do
      with_topic_repo do
        create_org(title: 'Org A')
        create_org(title: 'Org B')
        create_topic(title: 'Food', body: 'desc')
        audit = Mayhem::Topics::OrganizationAudit.new(client: FakeClient.new)
        processed = []
        write_called = false

        audit.stub(:process_org, ->(org, topic_list) { processed << [org, topic_list] }) do
          audit.stub(:write_report, -> { write_called = true }) do
            report = audit.run
            assert_equal audit.instance_variable_get(:@report), report
          end
        end

        topics = Mayhem::Models::Topic.all.to_a
        assert_equal 2, processed.length
        assert_equal ['Org A', 'Org B'], processed.map { |entry| entry[0].title }.sort
        assert_equal topics.map(&:title), processed.first[1].map(&:title)
        assert write_called
      end
    end
  end

  private

  def with_org_repo(&block)
    FMRepo::TestHelpers.with_temp_repo(role: :organizations, &block)
  end

  def with_news_repo(&block)
    FMRepo::TestHelpers.with_temp_repo(role: :news, &block)
  end

  def with_topic_repo(&block)
    FMRepo::TestHelpers.with_temp_repo(role: :topics, &block)
  end

  def create_org(title:, topic_titles: nil, summary: nil, description: nil, body: nil)
    front_matter = { 'title' => title, 'type' => 'Agency' }
    front_matter['topic_titles'] = topic_titles if topic_titles
    front_matter['summary'] = summary if summary
    front_matter['description'] = description if description
    Mayhem::Models::Organization.create!(front_matter, body: body.to_s)
  end

  def create_topic(title:, body:)
    Mayhem::Models::Topic.create!({ 'title' => title }, body: body)
  end

  def create_news(title:, date:, organization_title:, body:)
    Mayhem::Models::News.create!(
      {
        'title' => title,
        'date' => date,
        'organization_title' => organization_title,
        'summarized' => true
      },
      body: body.to_s
    )
  end
end
