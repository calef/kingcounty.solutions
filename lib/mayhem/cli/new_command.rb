# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'open3'
require 'date'
require 'time'

module Mayhem
  module CLI
    # Implements the "mayhem new" command to scaffold a Jekyll site with kingcounty.solutions configuration
    class NewCommand
      REQUIRED_PLUGINS = %w[
        jekyll-feed
        jekyll-last-modified-at
        jekyll-paginate-v2
        jekyll-seo-tag
        jekyll-sitemap
      ].freeze

      def initialize(args)
        @args = args
        @target_path = args.first
      end

      def run
        validate_dependencies
        validate_target_path
        setup_directory
        initialize_git_repo
        update_config
        install_plugins
        puts "✓ Successfully created new Jekyll site at #{@target_path}"
      end

      private

      def validate_dependencies
        validate_jekyll_installed
        validate_git_installed
      end

      def validate_jekyll_installed
        # Check if jekyll is available directly or via bundle
        if command_exists?('bundle')
          _stdout, _stderr, status = Open3.capture3('bundle', 'exec', 'jekyll', '--version')
          return if status.success?
        end

        return if command_exists?('jekyll')

        abort_with_error('Jekyll is not installed. Please install Jekyll first.')
      end

      def validate_git_installed
        return if command_exists?('git')

        abort_with_error('Git is not installed. Please install Git first.')
      end

      def command_exists?(command)
        stdout, _stderr, status = Open3.capture3("which #{command.split.first}")
        status.success? && !stdout.strip.empty?
      rescue StandardError
        false
      end

      def validate_target_path
        return if @target_path && !@target_path.empty?

        abort_with_error('Error: No target directory provided. Usage: mayhem new PATH')
      end

      def setup_directory
        if File.exist?(@target_path)
          handle_existing_directory
        else
          run_jekyll_new
        end
      end

      def handle_existing_directory
        config_path = File.join(@target_path, '_config.yml')
        return if File.exist?(config_path)

        warn "Directory #{@target_path} exists but has no _config.yml. Running jekyll new..."
        run_jekyll_new
      end

      def run_jekyll_new
        puts "Creating new Jekyll site at #{@target_path}..."
        # Try bundle exec jekyll first, fall back to jekyll
        success = if command_exists?('bundle')
                    system('bundle', 'exec', 'jekyll', 'new', @target_path, '--skip-bundle')
                  else
                    system('jekyll', 'new', @target_path, '--skip-bundle')
                  end
        abort_with_error("Failed to create Jekyll site at #{@target_path}") unless success
      end

      def initialize_git_repo
        return if git_repo?(@target_path)

        puts "Initializing git repository in #{@target_path}..."
        Dir.chdir(@target_path) do
          success = system('git', 'init')
          abort_with_error("Failed to initialize git repository in #{@target_path}") unless success
        end
      end

      def git_repo?(path)
        Dir.chdir(path) do
          _stdout, _stderr, status = Open3.capture3('git', 'rev-parse', '--git-dir')
          status.success?
        end
      rescue StandardError
        false
      end

      def update_config
        config_path = File.join(@target_path, '_config.yml')
        puts "Updating _config.yml with kingcounty.solutions configuration..."

        current_config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol])
        source_config = load_source_config

        # Add or replace configuration keys as specified
        current_config['ap_style'] = source_config['ap_style']
        current_config['collections'] = source_config['collections']
        current_config['content_max_age_days'] = 365
        current_config['defaults'] = source_config['defaults']
        current_config['future'] = true
        current_config['rss_max_item_age_days'] = 90
        current_config['timezone'] = 'America/Los_Angeles'

        File.write(config_path, YAML.dump(current_config))
      end

      def load_source_config
        # Navigate up from lib/mayhem/cli to repo root
        source_config_path = File.expand_path('../../../../_config.yml', __FILE__)
        YAML.safe_load_file(source_config_path, permitted_classes: [Date, Time, Symbol])
      end

      def install_plugins
        puts 'Installing Jekyll plugins...'

        gemfile_path = File.join(@target_path, 'Gemfile')
        gemfile_content = File.read(gemfile_path)

        # Check which plugins are already present
        missing_plugins = REQUIRED_PLUGINS.reject do |plugin|
          gemfile_content.include?("'#{plugin}'") || gemfile_content.include?("\"#{plugin}\"")
        end

        if missing_plugins.any?
          # Add missing plugins to the jekyll_plugins group
          plugin_lines = missing_plugins.map { |plugin| "  gem '#{plugin}'" }

          if gemfile_content.include?('group :jekyll_plugins do')
            # Insert plugins into existing group
            gemfile_content.sub!(
              /(group :jekyll_plugins do\n)/,
              "\\1#{plugin_lines.join("\n")}\n"
            )
          else
            # Add new jekyll_plugins group
            gemfile_content += "\ngroup :jekyll_plugins do\n#{plugin_lines.join("\n")}\nend\n"
          end

          File.write(gemfile_path, gemfile_content)
        end

        # Run bundle install with local path configuration
        Dir.chdir(@target_path) do
          puts 'Configuring bundler to install to vendor/bundle...'
          system('bundle', 'config', 'set', '--local', 'path', 'vendor/bundle')
          
          puts 'Running bundle install...'
          success = system('bundle', 'install')
          abort_with_error('Failed to install gems via bundler') unless success
        end
      end

      def abort_with_error(message)
        warn "Error: #{message}"
        exit 1
      end
    end
  end
end
