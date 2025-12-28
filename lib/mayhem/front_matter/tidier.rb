# frozen_string_literal: true

require 'mayhem/logging'
require 'mayhem/front_matter/document'
require 'mayhem/front_matter/spacing_normalizer'

module Mayhem
  module FrontMatter
    class Tidier
      include Mayhem::Loggable

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
        parsed = parse_markdown(content)
        normalized_body = normalize_body(parsed[:body], parsed[:front_matter])

        if parsed[:has_front_matter]
          Mayhem::FrontMatter::Document.build_markdown(parsed[:front_matter], normalized_body)
        else
          ensure_trailing_newline(normalized_body)
        end
      end

      def ensure_header_spacing(body)
        Mayhem::FrontMatter::SpacingNormalizer.normalize(body)
      end

      private

      def parse_markdown(content)
        result = Mayhem::FrontMatter::Document.parse(content)
        {
          front_matter: result.front_matter,
          body: result.body,
          raw: result.raw,
          has_front_matter: true
        }
      rescue Mayhem::FrontMatter::Document::ParseError => e
        raise unless missing_front_matter?(e)

        {
          front_matter: {},
          body: content,
          raw: content,
          has_front_matter: false
        }
      end

      def ensure_trailing_newline(content)
        content = content.to_s
        content.end_with?("\n") ? content : "#{content}\n"
      end

      def missing_front_matter?(error)
        error.message =~ /missing front matter/i
      end

      def normalize_body(body, front_matter)
        spacing_target = ensure_body_title(result_title(front_matter), body)
        spacing_target = convert_emphasis_headings(spacing_target)
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

      def convert_emphasis_headings(body)
        lines = body.to_s.each_line.to_a
        explicit_heading_level = 0
        in_fenced_code = false

        lines.each_with_index do |line, index|
          stripped = line.strip

          if stripped.start_with?('```', '~~~')
            in_fenced_code = !in_fenced_code
            next
          end
          next if in_fenced_code

          heading_level = heading_level_for_line(stripped)
          if heading_level
            explicit_heading_level = heading_level
            next
          end

          emphasized_title = extract_emphasized_title(stripped)
          next unless emphasized_title

          new_level = [explicit_heading_level + 1, 6].min
          lines[index] = "#{'#' * new_level} #{emphasized_title}\n"
        end

        lines.join
      end

      def extract_emphasized_title(line)
        stripped = line.to_s.strip
        match = stripped.match(/\A(\*{1,3}|_{1,3})(.+?)\1\z/)
        return unless match

        match[2].strip
      end

      def heading_level_for_line(line)
        match = line.match(/\A\s{0,3}(#+)\s+/)
        return unless match

        match[1].length
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
          logger.warn "Skipping non-Markdown target #{target}"
        end
      rescue Errno::ENOENT
        logger.warn "Target not found: #{target}"
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
        logger.info "Tidied front matter in #{path}"
      rescue Mayhem::FrontMatter::Document::ParseError => e
        logger.warn "Skipping #{path}: #{e.message}"
      end

      def markdown_file?(path)
        File.file?(path) && path.downcase.end_with?('.md')
      end
    end
  end
end
