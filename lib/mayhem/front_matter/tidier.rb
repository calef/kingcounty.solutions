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
        normalized_body = normalize_body(result.body, result.front_matter)
        Mayhem::FrontMatter::Document.build_markdown(result.front_matter, normalized_body)
      end

      def ensure_header_spacing(body)
        Mayhem::FrontMatter::SpacingNormalizer.normalize(body)
      end

      private

      def normalize_body(body, front_matter)
        spacing_target = ensure_body_title(result_title(front_matter), body)
        ensure_header_spacing(spacing_target)
      end

      def ensure_body_title(document_title, body)
        document_title = document_title.to_s.strip

        lines = body.to_s.each_line.to_a
        first_content_index = lines.index { |line| !line.strip.empty? }
        return body unless first_content_index

        emphasized_title = extract_emphasized_title(lines[first_content_index])
        return body unless emphasized_title

        if !document_title.empty? && titles_match?(document_title, emphasized_title)
          lines.delete_at(first_content_index)
        else
          lines[first_content_index] = "## #{emphasized_title.strip}\n"
        end
        lines.join
      end

      def extract_emphasized_title(line)
        stripped = line.to_s.strip
        match = stripped.match(/\A(\*{1,3}|_{1,3})(.+?)\1\z/)
        return unless match

        match[2].strip
      end

      def normalize_title(value)
        value.to_s
             .downcase
             .strip
             .gsub(/\s+/, ' ')
             .gsub(/\A[[:punct:]]+/, '')
             .gsub(/[[:punct:]]+\z/, '')
      end

      def titles_match?(document_title, emphasized_title)
        normalize_title(document_title) == normalize_title(emphasized_title)
      end

      def result_title(front_matter)
        return unless front_matter

        front_matter['title'] || front_matter[:title]
      end

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
