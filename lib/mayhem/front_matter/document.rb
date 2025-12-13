# frozen_string_literal: true

require 'yaml'
require 'date'
require 'time'

module Mayhem
  module FrontMatter
    # Convenience wrapper for reading and writing Markdown files that contain
    # YAML front matter. Centralizing the parsing logic ensures scripts share
    # consistent behavior and makes unit testing easier.
    class Document
      PERMITTED_CLASSES = [Date, Time].freeze

      ParseResult = Struct.new(:front_matter, :body, :raw, keyword_init: true)

      LOCK_KEY = 'locked'

      class ParseError < StandardError; end

      attr_reader :path
      attr_accessor :front_matter, :body

      class << self
        def load(path, logger: nil, permitted_classes: PERMITTED_CLASSES)
          parse(File.read(path), permitted_classes:).then do |result|
            new(path:, front_matter: result.front_matter, body: result.body)
          end
        rescue Errno::ENOENT
          logger&.trace("Missing file: #{path}")
          nil
        rescue ParseError => e
          logger&.warn("Failed to parse #{path}: #{e.message}")
          nil
        end

        def locked?(path, logger: nil)
          document = load(path, logger:)
          document&.locked?
        rescue StandardError
          false
        end

        def parse(content, permitted_classes: PERMITTED_CLASSES)
          match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
          raise ParseError, 'Missing front matter' unless match

          data = YAML.safe_load(
            match[1],
            permitted_classes: permitted_classes,
            aliases: true
          ) || {}

          body = match.post_match || ''
          ParseResult.new(front_matter: data, body: body, raw: content)
        rescue Psych::Exception => e
          raise ParseError, e.message
        end

        def build_markdown(front_matter, body)
          normalized_front_matter = normalize_front_matter(front_matter)
          yaml_segment = build_yaml_segment(normalized_front_matter)
          body_segment = normalize_body(body)
          build_document(yaml_segment, body_segment)
        end

        private

        def normalize_front_matter(front_matter)
          return {} unless front_matter

          front_matter.to_a.sort_by { |key, _| key.to_s }.to_h
        end

        def build_yaml_segment(front_matter)
          return '' if front_matter.empty?

          segment = YAML.dump(front_matter, indentation: 2)
          segment = segment.sub(/\A---\s*\n/, '')
          segment = segment.sub(/\.\.\.\s*\n\z/, '')
          strip_trailing_whitespace_from_lines(segment)
        end

        def strip_trailing_whitespace_from_lines(text)
          text.each_line.map(&:rstrip).join("\n")
        end

        def normalize_body(body)
          cleaned_body = body.to_s.sub(/\A\n+/, '')
          ensure_structured_spacing(strip_trailing_whitespace_from_lines(cleaned_body))
        end

        def ensure_structured_spacing(text)
          lines = text.each_line.map(&:rstrip)
          normalized = []
          in_list = false

          lines.each_with_index do |line, index|
            if header_line?(line)
              ensure_blank_line(normalized, allow_at_start: false)
              append_line(normalized, line)
              next_line = lines[index + 1]
              append_line(normalized, '') if next_line &&
                                             !blank_line?(next_line) &&
                                             !header_line?(next_line) &&
                                             !list_line?(next_line)
              in_list = false
            elsif list_line?(line)
              unless in_list
                ensure_blank_line(normalized, allow_at_start: false)
                in_list = true
              end
              append_line(normalized, line)
              next_line = lines[index + 1]
              if next_line.nil?
                append_blank_lines(normalized, count: 2, allow_duplicates: true)
                in_list = false
              elsif !list_line?(next_line)
                append_line(normalized, '') unless blank_line?(next_line)
                in_list = false
              end
            else
              append_line(normalized, line)
              in_list = false
            end
          end

          normalized.join("\n")
        end

        def header_line?(line)
          line.match?(/\A\s{0,3}\#{1,6}\s+/)
        end

        def list_line?(line)
          line.match?(/\A\s{0,3}(?:[-+*]|\d+\.)\s+/)
        end

        def blank_line?(line)
          line.nil? || line.strip.empty?
        end

        def ensure_blank_line(normalized, allow_at_start: true)
          return if normalized.empty? && !allow_at_start

          append_line(normalized, '', allow_duplicate_blank: false)
        end

        def append_blank_lines(normalized, count: 1, allow_duplicates: false)
          count.times { append_line(normalized, '', allow_duplicate_blank: allow_duplicates) }
        end

        def append_line(normalized, line, allow_duplicate_blank: false)
          trimmed = line.to_s
          return if trimmed.strip.empty? && normalized.last&.strip&.empty? && !allow_duplicate_blank

          normalized << trimmed
        end

        def build_document(yaml_segment, body_segment)
          sections = ['---', yaml_segment, '---', '']
          sections << body_segment unless body_segment.empty?
          content = sections.join("\n")
          content << "\n" unless content.end_with?("\n")
          content
        end
      end

      def initialize(path:, front_matter:, body:)
        @path = path
        @front_matter = front_matter || {}
        @body = body || ''
      end

      def [](key)
        @front_matter[key]
      end

      def []=(key, value)
        @front_matter[key] = value
      end

      def save(target_path = path)
        File.write(target_path, serialized_content)
      end

      def locked?
        @front_matter[LOCK_KEY] == true
      end

      private

      def serialized_content
        self.class.build_markdown(@front_matter, @body)
      end
    end
  end
end
