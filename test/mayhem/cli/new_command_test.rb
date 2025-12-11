# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../../../lib/mayhem/cli/new_command'

class NewCommandTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('mayhem_test')
    @target_path = File.join(@test_dir, 'test-site')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  def test_validates_target_path_is_provided
    command = Mayhem::CLI::NewCommand.new([])
    error = assert_raises(SystemExit) { command.run }
    assert_equal 1, error.status
  end

  def test_creates_config_with_required_keys
    skip 'Requires Jekyll and Bundler to be installed' unless jekyll_available? && bundle_available?

    command = Mayhem::CLI::NewCommand.new([@target_path])
    command.run

    config_path = File.join(@target_path, '_config.yml')
    assert File.exist?(config_path), 'Config file should exist'

    config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol])

    # Verify required keys are present
    assert config.key?('ap_style'), 'ap_style should be present'
    assert config.key?('collections'), 'collections should be present'
    assert_equal 365, config['content_max_age_days'], 'content_max_age_days should be 365'
    assert config.key?('defaults'), 'defaults should be present'
    assert_equal true, config['future'], 'future should be true'
    assert_equal 90, config['rss_max_item_age_days'], 'rss_max_item_age_days should be 90'
    assert_equal 'America/Los_Angeles', config['timezone'], 'timezone should be America/Los_Angeles'
  end

  def test_initializes_git_repository
    skip 'Requires Jekyll and Bundler to be installed' unless jekyll_available? && bundle_available?

    command = Mayhem::CLI::NewCommand.new([@target_path])
    command.run

    git_dir = File.join(@target_path, '.git')
    assert File.directory?(git_dir), 'Git repository should be initialized'
  end

  def test_installs_required_plugins
    skip 'Requires Jekyll and Bundler to be installed' unless jekyll_available? && bundle_available?

    command = Mayhem::CLI::NewCommand.new([@target_path])
    command.run

    gemfile_path = File.join(@target_path, 'Gemfile')
    assert File.exist?(gemfile_path), 'Gemfile should exist'

    gemfile_content = File.read(gemfile_path)

    # Check that required plugins are in the Gemfile
    Mayhem::CLI::NewCommand::REQUIRED_PLUGINS.each do |plugin|
      assert gemfile_content.include?(plugin), "Gemfile should include #{plugin}"
    end
  end

  def test_handles_existing_directory_with_config
    skip 'Requires Jekyll and Bundler to be installed' unless jekyll_available? && bundle_available?

    # Create a Jekyll site first
    command = Mayhem::CLI::NewCommand.new([@target_path])
    command.run

    # Run the command again on the same directory
    command2 = Mayhem::CLI::NewCommand.new([@target_path])
    command2.run

    # Should still have a valid config
    config_path = File.join(@target_path, '_config.yml')
    assert File.exist?(config_path), 'Config file should still exist'

    config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol])
    assert_equal 365, config['content_max_age_days'], 'Config should be updated'
  end

  private

  def jekyll_available?
    system('which jekyll > /dev/null 2>&1') || system('bundle exec jekyll --version > /dev/null 2>&1')
  end

  def bundle_available?
    system('which bundle > /dev/null 2>&1')
  end
end
