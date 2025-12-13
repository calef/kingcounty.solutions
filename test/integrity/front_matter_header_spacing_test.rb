# frozen_string_literal: true

require_relative '../test_helper'

class FrontMatterHeaderSpacingTest < Minitest::Test
  FRONT_MATTER_GLOBS = [
    '_posts/*.md',
    '_events/*.md',
    '_locations/*.md',
    '_organizations/*.md',
    '_topics/*.md',
    '_research_feeds/*.md',
    '_research_publications/*.md',
    '_research_sources/*.md',
    '_images/*.md'
  ].freeze

  def test_headers_have_blank_lines_before_and_after
    errors = []

    markdown_paths.each do |path|
      body, start_line = read_body_and_line(path)
      next if body.strip.empty?

      lines = body.each_line.to_a
      lines.each_with_index do |line, index|
        next unless header_line?(line)

        prev_line = index.positive? ? lines[index - 1] : nil
        unless index.zero? || blank_line?(prev_line)
          errors << "#{path} line #{start_line + index} must have a blank line before the header"
        end

        next_line = lines[index + 1]
        next if next_line.nil? || blank_line?(next_line)

        errors << "#{path} line #{start_line + index} must have a blank line after the header"
      end
    end

    assert_empty errors, "Header spacing issues:\n#{errors.join("\n")}"
  end

  private

  def markdown_paths
    FRONT_MATTER_GLOBS.flat_map { |glob| Dir[glob] }.sort
  end

  def read_body_and_line(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    return ['', content.count("\n") + 1] unless match

    body = match.post_match || ''
    start_line = content[0...match.end(0)].count("\n") + 1
    [body, start_line]
  end

  def header_line?(line)
    line.match?(/\A\s{0,3}\#{1,6}\s+/)
  end

  def blank_line?(line)
    line.nil? || line.strip.empty?
  end
end
