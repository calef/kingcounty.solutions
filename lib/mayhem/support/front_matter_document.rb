# frozen_string_literal: true

require 'yaml'
require 'date'
require 'time'

module Mayhem
  module Support
    # Convenience wrapper for reading and writing Markdown files that contain
    # YAML front matter. Centralizing the parsing logic ensures scripts share
    # consistent behavior and makes unit testing easier.
    class FrontMatterDocument
      PERMITTED_CLASSES = [Date, Time].freeze

      ParseResult = Struct.new(:front_matter, :body, :raw, keyword_init: true)

      class ParseError < StandardError; end

      attr_reader :path
      attr_accessor :front_matter, :body

      class << self
        def load(path, logger: nil, permitted_classes: PERMITTED_CLASSES)
          parse(File.read(path), permitted_classes:).then do |result|
            new(path:, front_matter: result.front_matter, body: result.body)
          end
        rescue Errno::ENOENT
          logger&.warn("Missing file: #{path}")
          nil
        rescue ParseError => e
          logger&.warn("Failed to parse #{path}: #{e.message}")
          nil
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
          segment.rstrip
        end

        def normalize_body(body)
          body.to_s.sub(/\A\n+/, '')
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

      private

      def serialized_content
        self.class.build_markdown(@front_matter, @body)
      end
    end
  end
end
