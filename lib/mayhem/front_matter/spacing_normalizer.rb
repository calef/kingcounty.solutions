# frozen_string_literal: true

module Mayhem
  module FrontMatter
    class SpacingNormalizer
      class << self
        def normalize(text)
          lines = text.to_s.each_line.map(&:rstrip)
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

          trim_trailing_blank_lines(normalized)

          normalized.join("\n")
        end

        private

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

        def ensure_blank_line(normalized, allow_at_start: true)
          return if normalized.empty? && !allow_at_start

          append_line(normalized, '', allow_duplicate_blank: false)
        end

        def append_line(normalized, line, allow_duplicate_blank: false)
          trimmed = line.to_s
          return if trimmed.strip.empty? && normalized.last&.strip&.empty? && !allow_duplicate_blank

          normalized << trimmed
        end

        def trim_trailing_blank_lines(lines)
          lines.pop while lines.any? && blank_line?(lines.last)
        end
      end
    end
  end
end
