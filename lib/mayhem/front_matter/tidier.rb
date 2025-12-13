# frozen_string_literal: true

require 'mayhem/logging'
require 'mayhem/front_matter/document'

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
        text = body.to_s
        return '' if text.empty?

        lines = text.each_line.map(&:rstrip)
        normalized_lines = []
        in_list = false

        lines.each_with_index do |line, index|
          if header_line?(line)
            ensure_blank_line(normalized_lines, allow_at_start: false)
            append_line(normalized_lines, line)
            next_line = lines[index + 1]
            append_line(normalized_lines, '') if next_line &&
                                                 !blank_line?(next_line) &&
                                                 !header_line?(next_line) &&
                                                 !list_line?(next_line)
            in_list = false
          elsif list_line?(line)
            unless in_list
              ensure_blank_line(normalized_lines, allow_at_start: false)
              in_list = true
            end
            append_line(normalized_lines, line)
            next_line = lines[index + 1]
            if next_line.nil?
              append_blank_lines(normalized_lines, count: 2, allow_duplicates: true)
              in_list = false
            elsif !list_line?(next_line)
              append_line(normalized_lines, '') unless blank_line?(next_line)
              in_list = false
            end
          else
            append_line(normalized_lines, line)
            in_list = false
          end
        end

        normalized_lines.join("\n")
      end

      def header_line?(line)
        return false if line.to_s.strip.empty?

        line.match?(/\A\s{0,3}\#{1,6}\s+/)
      end

      def list_line?(line)
        line.match?(/\A\s{0,3}(?:[-+*]|\d+\.)\s+/)
      end

      def blank_line?(line)
        line.nil? || line.strip.empty?
      end

      def append_blank_lines(normalized, count: 1, allow_duplicates: false)
        count.times { append_line(normalized, '', allow_duplicate_blank: allow_duplicates) }
      end

      def append_line(normalized, line, allow_duplicate_blank: false)
        trimmed = line.to_s
        return if trimmed.strip.empty? && normalized.last&.strip&.empty? && !allow_duplicate_blank

        normalized << trimmed
      end

      def ensure_blank_line(normalized, allow_at_start: true)
        return if normalized.empty? && !allow_at_start

        append_line(normalized, '', allow_duplicate_blank: false)
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
