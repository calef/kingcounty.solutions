# frozen_string_literal: true

require 'mayhem/logging'
require 'mayhem/front_matter/document'
require 'mayhem/front_matter/spacing_normalizer'

module Mayhem
  module FrontMatter
    class Tidier
      def initialize(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
        @logger = logger
      end

      # Rewrites every Markdown target (file or directory) so the front matter
      # keys are alphabetically ordered and the document is wrapped with a single
      # leading/trailing delimiter plus a blank line before the body.
      def tidy(target_paths)
        Array(target_paths).each do |target|
          tidy_target(target)
        end
      end

      # Public helper that normalizes a Markdown string according to the tidy rules.
      def tidy_markdown(content)
        result = Mayhem::FrontMatter::Document.parse(content)
        normalized_body = ensure_header_spacing(result.body)
        Mayhem::FrontMatter::Document.build_markdown(result.front_matter, normalized_body)
      end

      def ensure_header_spacing(body)
        Mayhem::FrontMatter::SpacingNormalizer.normalize(body)
      end

      private

      def tidy_target(target)
        path = File.expand_path(target)
        if File.directory?(path)
          tidy_directory(path)
        elsif markdown_file?(path)
          tidy_file(path)
        else
          @logger.warn "Skipping non-Markdown target #{target}"
        end
      rescue Errno::ENOENT
        @logger.warn "Target not found: #{target}"
      end

      def tidy_directory(directory)
        Dir.glob(File.join(directory, '**', '*.md')).each do |file|
          tidy_file(file)
        end
      end

      def tidy_file(path)
        content = File.read(path)
        normalized = tidy_markdown(content)
        return if normalized == content

        File.write(path, normalized)
        @logger.info "Tidied front matter in #{path}"
      rescue Mayhem::FrontMatter::Document::ParseError => e
        @logger.warn "Skipping #{path}: #{e.message}"
      end

      def markdown_file?(path)
        File.file?(path) && path.downcase.end_with?('.md')
      end
    end
  end
end
