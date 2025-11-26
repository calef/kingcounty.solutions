# frozen_string_literal: true

require 'tmpdir'
require 'logger'
require_relative 'test_helper'
require 'mayhem/front_matter_tidier'

class FrontMatterTidierTest < Minitest::Test
  def setup
    @tidier = Mayhem::FrontMatterTidier.new(logger: Logger.new(IO::NULL))
  end

  def test_tidy_markdown_sorts_keys_and_adds_blank_line
    original = <<~MD
      ---
      zeta: last
      alpha: first
      beta: second
      ---
      Body line
    MD

    result = @tidier.tidy_markdown(original)

    assert_match(/\A---\n/, result)
    assert_match(/alpha: first\nbeta: second\nzeta: last/, result)
    assert_match(/\n---\n\nBody line\n\z/, result)
  end

  def test_tidy_marks_directory_files
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'example.md')
      File.write(file, <<~MD)
        ---
        b: second
        a: first
        ---
        Body content
      MD

      @tidier.tidy(dir)
      content = File.read(file)

      assert_match(/a: first\nb: second/, content)
      assert_match(/\n---\n\nBody content\n\z/, content)
    end
  end

  def test_skips_invalid_front_matter
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'broken.md')
      File.write(file, 'No front matter here')

      @tidier.tidy(file)
      assert_equal 'No front matter here', File.read(file)
    end
  end
end
