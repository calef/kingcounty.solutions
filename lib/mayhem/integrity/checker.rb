# frozen_string_literal: true

require 'bundler'

module Mayhem
  module Integrity
    class Checker
      RUNNER_PATH = File.expand_path('../../../integrity/runner.rb', __dir__)

      def run(args = [])
        Dir.chdir(project_root) do
          run_command(RUNNER_PATH, args)
        end
      end

      private

      def project_root
        File.expand_path('../../..', __dir__)
      end

      def run_command(runner_path, args)
        command = ['bundle', 'exec', 'ruby', runner_path, *args]
        if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
          Bundler.with_unbundled_env { system(*command) }
        else
          system(*command)
        end
      end
    end
  end
end
