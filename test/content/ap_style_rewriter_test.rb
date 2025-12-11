# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/mayhem/content/ap_style_rewriter'

class ApStyleRewriterTest < Minitest::Test
  class FakeLogger
    attr_reader :infos, :warns, :errors, :debugs

    def initialize
      @infos = []
      @warns = []
      @errors = []
      @debugs = []
    end

    %i[info warn error debug].each do |level|
      define_method(level) do |message|
        instance_variable_get("@#{level}s") << message
      end
    end
  end

  class FakeChatClient
    attr_reader :calls

    def initialize(response: '')
      @response = response
      @calls = []
    end

    def call(**parameters)
      @calls << parameters
      @response
    end
  end

  def setup
    @tmp_dir = Dir.mktmpdir('ap-style')
    @logger = FakeLogger.new
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir)
  end

  def write_document(name, front_matter, body = '')
    path = File.join(@tmp_dir, name)
    content = Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, body)
    File.write(path, content)
    path
  end

  def build_rewriter(paths:, **options)
    defaults = {
      paths: paths,
      chat_client: FakeChatClient.new(response: 'Updated copy.'),
      logger: @logger
    }
    Mayhem::Content::ApStyleRewriter.new(**defaults.merge(options))
  end

  def assert_info_includes(text)
    assert @logger.infos.any? { |message| message.include?(text) }
  end

  def test_run_updates_body_and_records_stats
    file = write_document('item.md', { 'title' => 'Test' }, "Original text.")
    chat = FakeChatClient.new(response: 'Updated text.')
    rewriter = build_rewriter(paths: [file], chat_client: chat)

    stats = rewriter.run

    assert_equal 1, stats[:updated]
    document = Mayhem::Support::FrontMatterDocument.load(file)
    assert_equal "Updated text.\n", document.body
    assert_info_includes('Rewrote')
  end

  def test_run_dry_run_does_not_write
    file = write_document('item.md', { 'title' => 'Test' }, "Original text.")
    chat = FakeChatClient.new(response: 'Updated text.')
    rewriter = build_rewriter(paths: [file], chat_client: chat, dry_run: true)

    stats = rewriter.run

    assert_equal 1, stats[:would_update]
    document = Mayhem::Support::FrontMatterDocument.load(file)
    assert_equal "Original text.\n", document.body
    assert_info_includes('[dry-run]')
  end

  def test_run_skips_invalid_front_matter
    path = File.join(@tmp_dir, 'bad.md')
    File.write(path, 'no front matter here')
    rewriter = build_rewriter(paths: [path])

    stats = rewriter.run

    assert_equal 1, stats[:skipped_invalid_front_matter]
  end

  def test_run_skips_empty_body
    file = write_document('item.md', { 'title' => 'Title' }, "\n")
    rewriter = build_rewriter(paths: [file])

    stats = rewriter.run

    assert_equal 1, stats[:skipped_empty]
    assert_includes @logger.debugs.last, 'Skipping'
  end

  def test_rewrite_records_error_when_chat_returns_empty
    file = write_document('item.md', { 'title' => 'Test' }, "Original.")
    chat = FakeChatClient.new(response: '')
    rewriter = build_rewriter(paths: [file], chat_client: chat)

    stats = rewriter.run

    assert_equal 1, stats[:errors]
    assert_includes @logger.errors.last, 'LLM returned no content'
  end

  def test_rewrite_body_includes_metadata
    file = write_document('item.md', { 'title' => 'Title', 'source' => 'Source Org', 'topics' => ['Health'], 'date' => '2025-01-01' }, 'Body text')
    document = Mayhem::Support::FrontMatterDocument.load(file)
    chat = FakeChatClient.new(response: 'Updated body.')
    rewriter = build_rewriter(paths: [file], chat_client: chat)

    rewriter.send(:rewrite_body, document, 'Body text')

    prompt = chat.calls.last[:messages].find { |msg| msg[:role] == 'user' }[:content]
    assert_match(/title: Title/, prompt)
    assert_match(/source: Source Org/, prompt)
    assert_match(/topics: Health/, prompt)
    assert_match(/date: 2025-01-01/, prompt)
  end

  def test_run_warns_when_no_files
    dir = Dir.mktmpdir('empty')
    rewriter = build_rewriter(paths: [dir])

    stats = rewriter.run

    assert_equal 0, stats[:files_seen]
    assert_includes @logger.warns.last, 'No Markdown files matched'
  ensure
    FileUtils.remove_entry(dir)
  end
end
