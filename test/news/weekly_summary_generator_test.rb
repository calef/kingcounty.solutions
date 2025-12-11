# frozen_string_literal: true

require_relative '../test_helper'
require 'date'
require 'minitest/autorun'
require_relative '../../lib/mayhem/news/weekly_summary_generator'

class WeeklySummaryGeneratorTest < Minitest::Test
  class FakeLogger
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(message)
      @infos << message
    end

    def warn(_); end

    def debug(_); end
  end

  class FakeChatClient
    def initialize(response: "{}", raise_error: nil)
      @response = response
      @raise_error = raise_error
    end

    def call(*)
      raise @raise_error if @raise_error

      @response
    end
  end

  class FakeTopicClassifier
    def classify(_); []; end
  end

  def setup
    @tmp_posts = Dir.mktmpdir('posts')
    @logger = FakeLogger.new
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
  end

  def build_generator(overrides = {})
    options = {
      posts_dir: @tmp_posts,
      logger: @logger,
      client: Object.new,
      chat_client: FakeChatClient.new,
      topic_classifier: FakeTopicClassifier.new
    }.merge(overrides)
    Mayhem::News::WeeklySummaryGenerator.new(**options)
  end

  def write_post(filename, front_matter, body = '')
    path = File.join(@tmp_posts, filename)
    content = Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, body)
    File.write(path, content)
    path
  end

  def test_parsed_date_invalid_returns_nil
    gen = build_generator

    assert_nil gen.send(:parsed_date, 'not-a-date')
  end

  def test_fallback_summary_pluralization_and_other_updates
    write_post('2025-11-25-one.md',
               { 'title' => 'One', 'source' => 'S1', 'source_url' => 'http://1', 'summarized' => true }, 'p1')
    write_post('2025-11-26-two.md',
               { 'title' => 'Two', 'source' => 'S2', 'source_url' => 'http://2', 'summarized' => true }, 'p2')
    gen = build_generator
    posts = gen.send(:weekly_posts, Date.new(2025, 11, 24), Date.new(2025, 11, 30))

    assert_equal 2, posts.length

    plan = gen.send(:fallback_theme_plan, posts)
    body = gen.send(:fallback_summary, posts, Date.new(2025, 11, 24), Date.new(2025, 11, 30), plan)

    assert_includes body, 'We published 2 partner updates'
  end

  def test_fallback_summary_includes_other_updates_section
    write_post('2025-11-25-one.md',
               { 'title' => 'One', 'source' => 'S1', 'source_url' => 'http://1', 'summarized' => true }, 'p1')
    gen = build_generator
    posts = gen.send(:weekly_posts, Date.new(2025, 11, 24), Date.new(2025, 11, 30))
    plan = { 'themes' => [], 'other_ids' => posts.map { |post| post[:id] } }
    body = gen.send(:fallback_summary, posts, Date.new(2025, 11, 24), Date.new(2025, 11, 30), plan)

    assert_includes body, '### Other updates'
  end

  def test_current_week_range_aligns_to_saturday
    gen = build_generator
    start_date, end_date = gen.send(:current_week_range, Date.new(2025, 11, 26))

    assert_equal Date.new(2025, 11, 16), start_date
    assert_equal Date.new(2025, 11, 22), end_date
  end

  def test_human_range_formats_dates
    gen = build_generator
    range = gen.send(:human_range, Date.new(2025, 11, 17), Date.new(2025, 11, 23))

    assert_equal 'November 17–November 23, 2025', range
  end

  def test_build_context_includes_themes_sources_and_catalog
    gen = build_generator
    posts = [
      { id: '2025-11-25-one.md', title: 'One', date: Date.new(2025, 11, 25), source: 'S1', source_url: 'http://1', summary: 'p1', images: ['img1'] },
      { id: '2025-11-26-two.md', title: 'Two', date: Date.new(2025, 11, 26), source: 'S2', source_url: 'http://2', summary: 'p2', images: [] }
    ]
    plan = {
      'themes' => [
        { 'title' => 'Theme 1', 'summary' => 'Sum 1', 'post_ids' => ['2025-11-25-one.md'] }
      ],
      'other_ids' => ['2025-11-26-two.md']
    }
    context = gen.send(:build_context, posts, Date.new(2025, 11, 17), Date.new(2025, 11, 23), plan)

    assert_equal 2, context['post_count']
    assert_equal [{'source' => 'S1', 'count' => 1}, {'source' => 'S2', 'count' => 1}], context['top_sources']
    assert_equal 1, context['themes'].first['posts'].length
    assert_equal 1, context['other_posts'].length
    assert_equal posts.first[:summary], context['catalog']['2025-11-25-one.md']['summary']
  end

  def test_write_summary_writes_front_matter_and_returns_path
    gen = build_generator
    start_date = Date.new(2025, 11, 17)
    end_date = Date.new(2025, 11, 23)
    dest = nil
    dest = gen.send(:write_summary, start_date, end_date, 'body', 'gpt-test', %w[t1], %w[i1])

    assert File.exist?(dest)
    document = Mayhem::Support::FrontMatterDocument.load(dest)
    assert_equal 'King County Solutions Weekly Roundup: November 17–November 23, 2025', document.front_matter['title']
    assert_equal 'gpt-test', document.front_matter['openai_model']
    assert_equal %w[i1], document.front_matter['images']
  ensure
    File.delete(dest) if dest && File.exist?(dest)
  end

  def test_weekly_posts_filters_unpublished_and_missing_content
    write_post('2025-11-24-unpublished.md',
               { 'title' => 'Skip', 'published' => false, 'source_url' => 'http://skip', 'original_content' => 'x' }, 'body')
    write_post('2025-11-25-valid.md',
               { 'title' => 'Keep', 'source' => 'S', 'source_url' => 'http://keep', 'original_content' => 'y', 'summary' => 'text' }, 'body')
    gen = build_generator
    posts = gen.send(:weekly_posts, Date.new(2025, 11, 24), Date.new(2025, 11, 30))

    assert_equal 1, posts.length
    assert_equal 'Keep', posts.first[:title]
    assert_equal 'body', posts.first[:summary]
  end

  def test_build_theme_plan_falls_back_after_llm_failure
    posts = [
      { id: '2025-11-25-one.md', title: 'One', date: Date.new(2025, 11, 25), source: 'S1', source_url: 'http://1', summary: 'p1', images: [] }
    ]
    generator = build_generator(chat_client: FakeChatClient.new(raise_error: StandardError.new('boom')))
    plan = generator.send(:build_theme_plan, posts)

    assert_equal 'Key regional updates', plan['themes'].first['title']
  end

  def test_generate_summary_body_fallbacks_to_heuristic
    posts = [
      { id: '2025-11-25-one.md', title: 'One', date: Date.new(2025, 11, 25), source: 'S1', source_url: 'http://1', summary: 'p1', images: [] }
    ]
    plan = { 'themes' => [], 'other_ids' => [] }
    generator = build_generator(chat_client: FakeChatClient.new(raise_error: StandardError.new('boom')))
    context = { 'window' => { 'end' => Date.new(2025, 11, 30).to_s } }
    prompt = generator.send(:build_prompt, context)
    body, model_used = generator.send(:generate_summary_body, prompt, posts, Date.new(2025, 11, 23), Date.new(2025, 11, 30), plan)

    assert_equal 'fallback', model_used
    assert_includes body, 'We published'
  end

end
