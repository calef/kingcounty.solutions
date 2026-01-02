# frozen_string_literal: true

require_relative '../test_helper'

require 'mayhem/content/source_url_checker'
require 'mayhem/events/ical_importer'
require 'mayhem/events/stale_event_cleaner'
require 'mayhem/events/summarizer'
require 'mayhem/front_matter/tidier'
require 'mayhem/images/extractor'
require 'mayhem/integrity/checker'
require 'mayhem/news/content_age_enforcer'
require 'mayhem/news/event_extractor'
require 'mayhem/news/rss_importer'
require 'mayhem/news/summarizer'
require 'mayhem/openai/model_lister'
require 'mayhem/organizations/generator'
require 'mayhem/organizations/pruner'
require 'mayhem/topics/organization_audit'
require 'mayhem/websites/generator'
require 'seldon'

# Load the CLI module from bin/mayhem
load File.expand_path('../../bin/mayhem', __dir__)

class MayhemCLITest < Minitest::Test
  def test_run_ingest_calls_check_integrity_at_end
    # Track which methods are called and in what order
    calls = []

    Mayhem::CLI.stub(:run_import_content, ->(_args) { calls << :run_import_content }) do
      Mayhem::CLI.stub(:run_summarize, ->(_args) { calls << :run_summarize }) do
        Mayhem::CLI.stub(:run_extract_events, ->(_args) { calls << :run_extract_events }) do
          Mayhem::CLI.stub(:run_extract_images, ->(_args) { calls << :run_extract_images }) do
            Mayhem::CLI.stub(:run_expire, ->(_args) { calls << :run_expire }) do
              Mayhem::CLI.stub(:run_check_integrity, ->(_args) { calls << :run_check_integrity }) do
                Mayhem::CLI.run_ingest([])
              end
            end
          end
        end
      end
    end

    # Verify all methods were called
    assert_includes calls, :run_import_content
    assert_includes calls, :run_summarize
    assert_includes calls, :run_extract_events
    assert_includes calls, :run_extract_images
    assert_includes calls, :run_expire
    assert_includes calls, :run_check_integrity

    # Verify run_check_integrity is called after run_expire (at the end)
    expire_index = calls.index(:run_expire)
    integrity_index = calls.index(:run_check_integrity)
    assert integrity_index > expire_index, 'check_integrity should be called after expire'
    assert_equal calls.last, :run_check_integrity, 'check_integrity should be the last call'
  end

  def test_run_help_shows_help_and_exits
    called = false

    Mayhem::CLI.stub(:show_help, -> { called = true }) do
      error = assert_raises(SystemExit) { Mayhem::CLI.run([]) }
      assert_equal 0, error.status
    end

    assert called
  end

  def test_run_unknown_command_exits_nonzero
    error = nil

    Mayhem::CLI.stub(:show_help, -> {}) do
      _out, err = capture_io do
        error = assert_raises(SystemExit) { Mayhem::CLI.run(['nope']) }
      end

      assert_equal 1, error.status
      assert_includes err, 'Unknown command: nope'
    end
  end

  def test_run_dispatches_command
    args_received = nil

    Mayhem::CLI.stub(:run_tidy, ->(args) { args_received = args }) do
      Mayhem::CLI.run(['tidy', 'path/to/file'])
    end

    assert_equal ['path/to/file'], args_received
  end

  def test_show_help_lists_commands
    out, = capture_io { Mayhem::CLI.show_help }

    assert_includes out, 'Usage: mayhem COMMAND'
    assert_includes out, 'Available commands:'
    assert_includes out, 'audit-topics'
  end

  def test_parse_audit_topics_options_defaults
    options = Mayhem::CLI.parse_audit_topics_options([], default_model: 'model-x', default_max_posts: 10)

    assert_equal 'model-x', options[:model]
    assert_equal 10, options[:max_posts]
    refute options[:force]
    assert_nil options[:output]
    refute options[:apply]
  end

  def test_parse_audit_topics_options_overrides
    args = ['--model', 'gpt-4', '--max-posts', '3', '--force', '--output', 'report.json', '--apply']
    options = Mayhem::CLI.parse_audit_topics_options(args, default_model: 'model-x', default_max_posts: 10)

    assert_equal 'gpt-4', options[:model]
    assert_equal 3, options[:max_posts]
    assert options[:force]
    assert_equal 'report.json', options[:output]
    assert options[:apply]
  end

  def test_run_audit_topics_builds_client_and_runs
    previous_key = ENV['OPENAI_API_KEY']
    ENV['OPENAI_API_KEY'] = 'token'

    options = { model: 'gpt-4', max_posts: 5, force: true, output: 'out.json', apply: true }
    parsed_args = nil
    client_args = nil
    audit_args = nil
    audit = Minitest::Mock.new
    audit.expect(:run, nil)
    client = Object.new

    Mayhem::CLI.stub(:parse_audit_topics_options, ->(args, **_defaults) { parsed_args = args; options }) do
      OpenAI::Client.stub(:new, ->(**args) { client_args = args; client }) do
        Mayhem::Topics::OrganizationAudit.stub(:new, ->(**args) { audit_args = args; audit }) do
          Mayhem::CLI.run_audit_topics(['--force'])
        end
      end
    end

    audit.verify
    assert_equal ['--force'], parsed_args
    assert_equal({ access_token: 'token' }, client_args)
    assert_equal client, audit_args[:client]
    assert_equal 'gpt-4', audit_args[:model]
    assert_equal 5, audit_args[:max_posts]
    assert_equal true, audit_args[:force]
    assert_equal 'out.json', audit_args[:output]
    assert_equal true, audit_args[:apply]
  ensure
    if previous_key
      ENV['OPENAI_API_KEY'] = previous_key
    else
      ENV.delete('OPENAI_API_KEY')
    end
  end

  def test_run_check_integrity_help
    checker_called = false

    Mayhem::Integrity::Checker.stub(:new, -> { checker_called = true }) do
      out, = capture_io { Mayhem::CLI.run_check_integrity(['--help']) }

      assert_includes out, 'Usage: mayhem check-integrity'
    end

    refute checker_called
  end

  def test_run_check_integrity_failure_exits
    checker = Minitest::Mock.new
    checker.expect(:run, false, [[]])

    Mayhem::Integrity::Checker.stub(:new, checker) do
      error = nil

      _out, err = capture_io do
        error = assert_raises(SystemExit) { Mayhem::CLI.run_check_integrity([]) }
      end

      assert_equal 1, error.status
      assert_includes err, 'Integrity checks failed'
    end

    checker.verify
  end

  def test_run_check_integrity_success
    checker = Minitest::Mock.new
    checker.expect(:run, true, [['--name', 'foo']])

    Mayhem::Integrity::Checker.stub(:new, checker) do
      Mayhem::CLI.run_check_integrity(['--name', 'foo'])
    end

    checker.verify
  end

  def test_run_check_source_urls
    checker = Minitest::Mock.new
    checker.expect(:run, nil)

    Mayhem::Content::SourceUrlChecker.stub(:new, checker) do
      Mayhem::CLI.run_check_source_urls([])
    end

    checker.verify
  end

  def test_run_create_organization_requires_url
    error = nil

    _out, err = capture_io do
      error = assert_raises(SystemExit) { Mayhem::CLI.run_create_organization([]) }
    end

    assert_equal 1, error.status
    assert_includes err, 'Usage: mayhem create-organization'
  end

  def test_run_create_organization_runs_generator
    generator = Minitest::Mock.new
    generator.expect(:run, nil, ['https://example.com'])

    Mayhem::Organizations::Generator.stub(:new, generator) do
      Mayhem::CLI.run_create_organization(['https://example.com'])
    end

    generator.verify
  end

  def test_run_create_website_requires_url
    error = nil

    _out, err = capture_io do
      error = assert_raises(SystemExit) { Mayhem::CLI.run_create_website([]) }
    end

    assert_equal 1, error.status
    assert_includes err, 'Usage: mayhem create-website'
  end

  def test_run_create_website_runs_generator
    generator = Minitest::Mock.new
    generator.expect(:run, nil, ['https://example.com'])

    Mayhem::Websites::Generator.stub(:new, generator) do
      Mayhem::CLI.run_create_website(['https://example.com'])
    end

    generator.verify
  end

  def test_run_delete_organization_requires_title
    error = nil

    _out, err = capture_io do
      error = assert_raises(SystemExit) { Mayhem::CLI.run_delete_organization([]) }
    end

    assert_equal 1, error.status
    assert_includes err, 'Usage: mayhem delete-organization'
  end

  def test_run_delete_organization_runs_pruner
    logger = Object.new
    logger_args = nil
    pruner_title = nil
    logger_set = nil

    Seldon::Logging.stub(:build_logger, ->(**args) { logger_args = args; logger }) do
      Seldon::Logging.stub(:logger=, ->(value) { logger_set = value }) do
        Mayhem::Organizations::Pruner.stub(:prune, ->(title) { pruner_title = title }) do
          Mayhem::CLI.run_delete_organization(['Org'])
        end
      end
    end

    assert_equal({ env_var: 'LOG_LEVEL', default_level: 'INFO', program_name: 'mayhem' }, logger_args)
    assert_equal logger, logger_set
    assert_equal 'Org', pruner_title
  end

  def test_run_expire_runs_cleanup
    content = Minitest::Mock.new
    content.expect(:run, nil)
    events = Minitest::Mock.new
    events.expect(:run, nil)

    Mayhem::News::ContentAgeEnforcer.stub(:new, content) do
      Mayhem::Events::StaleEventCleaner.stub(:new, events) do
        Mayhem::CLI.run_expire([])
      end
    end

    content.verify
    events.verify
  end

  def test_run_extract_events
    extractor = Minitest::Mock.new
    extractor.expect(:run, nil)

    Mayhem::News::EventExtractor.stub(:new, extractor) do
      Mayhem::CLI.run_extract_events([])
    end

    extractor.verify
  end

  def test_run_extract_images
    extractor = Minitest::Mock.new
    extractor.expect(:run, nil)

    Mayhem::Images::Extractor.stub(:new, extractor) do
      Mayhem::CLI.run_extract_images([])
    end

    extractor.verify
  end

  def test_run_import_content
    rss = Minitest::Mock.new
    rss.expect(:run, nil)

    Mayhem::News::RssImporter.stub(:new, rss) do
      Mayhem::Events::IcalImporterCLI.stub(:run, nil) do
        Mayhem::CLI.run_import_content([])
      end
    end

    rss.verify
  end

  def test_run_ls_models
    lister = Minitest::Mock.new
    lister.expect(:run, nil)

    Mayhem::OpenAI::ModelLister.stub(:new, lister) do
      Mayhem::CLI.run_ls_models([])
    end

    lister.verify
  end

  def test_run_summarize_logs_result
    logger = Minitest::Mock.new
    logger.expect(:info, nil, ['summarize complete: 5 files updated'])

    news = Minitest::Mock.new
    news.expect(:run, { updated: 2 })

    events = Minitest::Mock.new
    events.expect(:run, { updated: 3 })

    Seldon::Logging.stub(:build_logger, ->(**_args) { logger }) do
      Mayhem::News::PostSummarizer.stub(:new, news) do
        Mayhem::Events::EventSummarizer.stub(:new, events) do
          Mayhem::CLI.run_summarize([])
        end
      end
    end

    logger.verify
    news.verify
    events.verify
  end

  def test_run_tidy_requires_paths
    error = nil

    _out, err = capture_io do
      error = assert_raises(SystemExit) { Mayhem::CLI.run_tidy([]) }
    end

    assert_equal 1, error.status
    assert_includes err, 'Usage: mayhem tidy'
  end

  def test_run_tidy_runs_tidier
    tidier = Minitest::Mock.new
    tidier.expect(:tidy, nil, [['file1.md', 'dir']])

    Mayhem::FrontMatter::Tidier.stub(:new, tidier) do
      Mayhem::CLI.run_tidy(['file1.md', 'dir'])
    end

    tidier.verify
  end

  def test_help_requested
    assert Mayhem::CLI.help_requested?(['--help'])
    assert Mayhem::CLI.help_requested?(['-h'])
    refute Mayhem::CLI.help_requested?(['--name', 'foo'])
  end
end
