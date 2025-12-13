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
            normalized_lines << '' unless normalized_lines.empty? || blank_line?(normalized_lines.last)
            normalized_lines << line
            next_line = lines[index + 1]
            normalized_lines << '' if next_line &&
                                      !blank_line?(next_line) &&
                                      !header_line?(next_line) &&
                                      !list_line?(next_line)
            in_list = false
          elsif list_line?(line)
            unless in_list
              normalized_lines << '' unless normalized_lines.empty? || blank_line?(normalized_lines.last)
              in_list = true
            end
            normalized_lines << line
            next_line = lines[index + 1]
            if next_line.nil?
              normalized_lines << ''
              normalized_lines << ''
              in_list = false
            elsif !list_line?(next_line)
              normalized_lines << '' unless blank_line?(next_line)
              in_list = false
            end
          else
            normalized_lines << line
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
