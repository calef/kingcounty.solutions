# frozen_string_literal: true

require 'test_helper'

class PottymouthWordsTest < Minitest::Test
  WORDLIST_PATH = File.expand_path('support/pottymouth_words.txt', __dir__)
  IGNORED_DIRECTORIES = %w[_site coverage node_modules vendor].freeze

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
    [].tap do |offenses|
      File.foreach(path).with_index(1) do |line, line_number|
        line.scan(pottymouth_regex) do |match|
          next if allowed_use?(match, line)

          offenses << "#{path}:#{line_number} contains '#{match}'"
        end
      end
    end
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
