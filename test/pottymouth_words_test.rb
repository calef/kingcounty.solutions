# frozen_string_literal: true

require 'test_helper'

class PottymouthWordsTest < Minitest::Test
  WORDLIST_PATH = File.expand_path('support/pottymouth_words.txt', __dir__)
  IGNORED_DIRECTORIES = %w[_site coverage node_modules vendor].freeze
  PATTERN_FIELDS = %w[original_content original_markdown_body].freeze

  def test_markdown_files_are_free_of_pottymouth_words
    offenses = markdown_paths.flat_map { |path| offenses_in_file(path) }

    assert_empty offenses, "Pottymouth words detected:\n#{offenses.join("\n")}"
  end

  private

  def markdown_paths
    Dir.glob('**/*.md').reject do |path|
      IGNORED_DIRECTORIES.any? { |dir| path.start_with?("#{dir}/") }
    end
  end

  def offenses_in_file(path)
    skip_lines = front_matter_skip_lines(path)

    [].tap do |offenses|
      File.foreach(path).with_index(1) do |line, line_number|
        next if skip_lines.include?(line_number)

        line.scan(pottymouth_regex) do |match|
          next if allowed_use?(match, line)

          offenses << "#{path}:#{line_number} contains '#{match}'"
        end
      end
    end
  end

  def front_matter_skip_lines(path)
    lines = File.readlines(path)
    front_start = lines.index { |line| line.strip == '---' }
    return Set.new unless front_start

    front_end_index = lines[(front_start + 1)..].index { |line| line.strip == '---' }
    return Set.new unless front_end_index

    front_end = front_start + 1 + front_end_index
    skipped = Set.new

    i = front_start + 1
    while i < front_end
      line = lines[i]
      if line.match(/^\s*(#{PATTERN_FIELDS.join('|')}):/)
        skipped << (i + 1)
        j = i + 1
        while j < front_end
          next_line = lines[j]
          break if next_line.strip != '' && next_line !~ /\A\s+/

          skipped << (j + 1)
          j += 1
        end
        i = j
      else
        i += 1
      end
    end

    skipped
  rescue Errno::ENOENT
    Set.new
  end

  def pottymouth_regex
    @pottymouth_regex ||= begin
      escaped_words = pottymouth_words.map { |word| Regexp.escape(word) }
      /\b(?:#{escaped_words.join('|')})\b/i
    end
  end

  def pottymouth_words
    File.readlines(WORDLIST_PATH)
        .map { |line| line.strip.downcase }
        .reject { |line| line.empty? || line.start_with?('#') }
  end

  def allowed_use?(match, line)
    return false unless match.casecmp('cum').zero?

    normalized = line.downcase
    normalized.include?('summa cum laude') || normalized.include?('magnum cum laude')
  end
end
