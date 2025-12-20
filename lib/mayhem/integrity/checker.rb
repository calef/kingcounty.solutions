# frozen_string_literal: true

require 'bundler'

module Mayhem
  module Integrity
    class Checker
      RUNNER_PATH = File.expand_path('../../../integrity/runner.rb', __dir__)

      def run(args = [])
        Dir.chdir(project_root) do
          unless run_build
            warn 'Jekyll build failed'
            return false
          end

          run_tests(args)
        end
      end

      private

      def project_root
        File.expand_path('../../..', __dir__)
      end

      def run_build
        system('bundle', 'exec', 'jekyll', 'build')
      end

      def run_tests(args)
        system('bundle', 'exec', 'ruby', RUNNER_PATH, *args)
      end
    end
  end
end
