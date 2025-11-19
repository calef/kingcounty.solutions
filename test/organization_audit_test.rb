# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require 'yaml'
require_relative '../lib/topic_audit'

class FakeOpenAIClient
  attr_reader :calls

  def initialize(responses)
    @responses = responses.dup
    @calls = 0
  end

  def chat(parameters:)
    raise 'No fake responses configured' if @responses.empty?

    @calls += 1
    @responses.shift
  end
end

class OrganizationAuditTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir('topic-audit-test')
    @org_dir = File.join(@tmp_dir, 'orgs')
    @topic_dir = File.join(@tmp_dir, 'topics')
    @posts_dir = File.join(@tmp_dir, 'posts')
    @cache_dir = File.join(@tmp_dir, 'cache')
    @report_path = File.join(@tmp_dir, 'report.json')
    FileUtils.mkdir_p([@org_dir, @topic_dir, @posts_dir])
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir)
  end

  def test_run_writes_report_without_altering_files_by_default
    write_topic('Food Support')
    write_topic('Housing Support')
    write_org('example-org.md', title: 'Example Org', topics: ['Food Support'])

    client = FakeOpenAIClient.new([
      chat_success_response(
        'topics_true' => ['Housing Support'],
        'topics_false' => ['Food Support'],
        'topics_unclear' => [],
        'notes' => 'Focus has shifted.'
      )
    ])

    audit = build_audit(client: client)
    audit.run

    report = JSON.parse(File.read(@report_path))
    entry = report.fetch(0)
    assert_equal 'Example Org', entry['org']
    assert_equal ['Housing Support'], entry['additions']
    assert_equal ['Food Support'], entry['removals']
    assert_equal [], entry['unclear']
    assert_equal 'Focus has shifted.', entry['notes']

    front_matter = read_front_matter(File.join(@org_dir, 'example-org.md'))
    assert_equal ['Food Support'], front_matter['topics'], 'topics should remain unchanged without --apply'
  end

  def test_run_with_apply_updates_front_matter
    write_topic('Housing Support')
    write_org('apply-org.md', title: 'Apply Org', topics: ['Food Support'])

    client = FakeOpenAIClient.new([
      chat_success_response(
        'topics_true' => ['Housing Support', 'Food Support'],
        'topics_false' => [],
        'topics_unclear' => []
      )
    ])

    audit = build_audit(client: client, apply: true)
    audit.run

    front_matter = read_front_matter(File.join(@org_dir, 'apply-org.md'))
    assert_equal ['Food Support', 'Housing Support'], front_matter['topics']
  end

  def test_run_uses_cached_response_when_available
    write_topic('Housing Support')
    write_org('cache-org.md', title: 'Cache Org', topics: [])

    first_client = FakeOpenAIClient.new([
      chat_success_response(
        'topics_true' => ['Housing Support'],
        'topics_false' => [],
        'topics_unclear' => []
      )
    ])
    build_audit(client: first_client).run
    assert_equal 1, first_client.calls

    cached_client = FakeOpenAIClient.new([])
    cached_report = File.join(@tmp_dir, 'cached-report.json')
    build_audit(client: cached_client, output: cached_report).run
    assert_equal 0, cached_client.calls, 'cache should be reused so no API calls occur'

    report = JSON.parse(File.read(cached_report))
    entry = report.fetch(0)
    assert_equal ['Housing Support'], entry['additions']
  end

  private

  def build_audit(client:, apply: false, force: false, output: nil)
    options = {
      model: 'fake-model',
      max_posts: 2,
      force: force,
      output: output || @report_path,
      apply: apply
    }

    TopicAudit::OrganizationAudit.new(
      client: client,
      options: options,
      org_dir: @org_dir,
      topic_dir: @topic_dir,
      posts_dir: @posts_dir,
      cache_dir: @cache_dir
    )
  end

  def chat_success_response(payload)
    {
      'choices' => [
        { 'message' => { 'content' => JSON.generate(payload) } }
      ]
    }
  end

  def write_topic(title)
    front_matter = { 'title' => title }
    write_document(File.join(@topic_dir, "#{title.downcase.tr(' ', '-')}.md"), front_matter, "Summary for #{title}.")
  end

  def write_org(filename, title:, topics:)
    front_matter = {
      'title' => title,
      'topics' => topics,
      'summary' => "#{title} summary",
      'description' => "#{title} description"
    }
    write_document(File.join(@org_dir, filename), front_matter, "#{title} body")
  end

  def write_document(path, front_matter, body)
    yaml = YAML.dump(front_matter).sub(/\A---\s*\n/, '').strip
    File.write(path, ['---', yaml, '---', body].join("\n"))
  end

  def read_front_matter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    match ? YAML.safe_load(match[1]) : {}
  end
end
