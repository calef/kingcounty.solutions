# frozen_string_literal: true

require 'tmpdir'
require 'logger'
require_relative '../../test_helper'
require 'mayhem/front_matter/tidier'

class FrontMatterTidierTest < Minitest::Test
  def setup
    @tidier = Mayhem::FrontMatter::Tidier.new(logger: Logger.new(IO::NULL))
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

  def test_tidy_markdown_uses_two_space_indents
    original = <<~MD
      ---
      nested:
            child: value
      ---
      Body
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, '  child: value'
    refute_includes result, '    child: value'
  end

  def test_removes_emphasized_title_when_matching_document_title
    original = <<~MD
      ---
      title: A Happy Reunion One Year Later!
      ---

      **A Happy Reunion One Year Later**

      Body paragraph.
    MD

    result = @tidier.tidy_markdown(original)

    refute_includes result, '**A Happy Reunion One Year Later**'
    refute_includes result, '# A Happy Reunion One Year Later!'
    assert_includes result, "Body paragraph.\n"
  end

  def test_converts_emphasis_to_heading_when_title_differs
    original = <<~MD
      ---
      title: City Manager Report – October 9, 2025
      ---

      **Normandy Park City Manager Reports - October/November 2025**

      Body paragraph.
    MD

    result = @tidier.tidy_markdown(original)

    refute_includes result, '**Normandy Park City Manager Reports - October/November 2025**'
    assert_includes result, "## Normandy Park City Manager Reports - October/November 2025\n\nBody paragraph.\n"
  end

  def test_converts_italicized_emphasis_to_heading
    original = <<~MD
      ---
      title: Event Title
      ---

      _Completely Different Title_

      Body paragraph.
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "## Completely Different Title\n\nBody paragraph.\n"
  end

  def test_titles_match_strips_punctuation_and_spacing
    assert @tidier.send(:titles_match?, 'Great News!', '  Great News ')
    refute @tidier.send(:titles_match?, 'Different', 'Great News')
  end
end
