# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative 'test_helper'
require_relative '../lib/mayhem/topics/organization_audit'
require_relative '../lib/mayhem/support/front_matter_document'

class OrganizationAuditTest < Minitest::Test
  class StubClient
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def chat(parameters:)
      @calls << parameters
      {
        'choices' => [
          {
            'message' => {
              'content' => @response
            }
          }
        ]
      }
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir('org-audit')
    @org_dir = File.join(@tmpdir, 'orgs')
    @topic_dir = File.join(@tmpdir, 'topics')
    @posts_dir = File.join(@tmpdir, 'posts')
    @cache_dir = File.join(@tmpdir, 'cache')
    FileUtils.mkdir_p([@org_dir, @topic_dir, @posts_dir, @cache_dir])
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_updates_topics_when_apply_enabled
    write_topic('housing', title: 'Housing', summary: 'Housing support services.')
    write_org('help-center', title: 'Help Center', website: 'https://example.org')
    write_post('2024-01-01-update', title: 'Update', date: '2024-01-01', source: 'Help Center')

    client = StubClient.new({
                              topics_true: ['Housing'],
                              topics_false: [],
                              topics_unclear: [],
                              notes: 'Focuses on housing'
                            }.to_json)

    audit = Mayhem::Topics::OrganizationAudit.new(
      client: client,
      model: 'test-model',
      max_posts: 1,
      force: true,
      output: nil,
      apply: true,
      org_dir: @org_dir,
      topic_dir: @topic_dir,
      posts_dir: @posts_dir,
      cache_dir: @cache_dir,
      logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
    )

    audit.run

    document = Mayhem::Support::FrontMatterDocument.load(File.join(@org_dir, 'help-center.md'))
    assert_equal ['Housing'], document.front_matter['topics']
    assert File.exist?(File.join(@cache_dir, 'help_center.json')), 'expected cache file to be written'
  end

  private

  def write_topic(slug, title:, summary:)
    path = File.join(@topic_dir, "#{slug}.md")
    File.write(
      path,
      <<~MARKDOWN
        ---
        title: #{title}
        ---
        #{summary}
      MARKDOWN
    )
  end

  def write_org(slug, title:, website:)
    path = File.join(@org_dir, "#{slug}.md")
    File.write(
      path,
      <<~MARKDOWN
        ---
        title: #{title}
        website: #{website}
        ---
        Description here.
      MARKDOWN
    )
  end

  def write_post(slug, title:, date:, source:)
    path = File.join(@posts_dir, "#{date}-#{slug}.md")
    File.write(
      path,
      <<~MARKDOWN
        ---
        title: #{title}
        date: #{date}
        source: #{source}
        ---
        Body content.
      MARKDOWN
    )
  end
end
