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

  def test_skips_files_with_unparseable_front_matter
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'broken.md')
      File.write(file, <<~MD)
        ---
        this: [is not valid
      MD

      @tidier.tidy(file)

      assert_equal <<~MD, File.read(file)
        ---
        this: [is not valid
      MD
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

  def test_tidy_markdown_without_front_matter_preserves_body_only
    original = <<~MD
      **Standalone Title**

      Body paragraph.
    MD

    result = @tidier.tidy_markdown(original)

    refute_match(/\A---/, result)
    assert_includes result, "## Standalone Title\n\nBody paragraph.\n"
  end

  def test_tidy_updates_files_without_front_matter
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'plain.md')
      File.write(file, "Just body text")

      @tidier.tidy(file)

      content = File.read(file)
      refute_match(/\A---/, content)
      assert_equal "Just body text\n", content
    end
  end

  def test_tables_are_surrounded_by_blank_lines
    original = <<~MD
      ---
      title: Table Doc
      ---
      Intro paragraph.
      | Col1 | Col2 |
      | ---- | ---- |
      | A    | B    |
      Following paragraph.
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "Intro paragraph.\n\n| Col1 | Col2 |\n| ---- | ---- |\n| A    | B    |\n\nFollowing paragraph.\n"
  end

  def test_emphasis_under_header_converts_to_next_heading_level
    original = <<~MD
      ---
      title: Nested Headers
      ---
      ### Parent
      **Child Header**
      Content line.
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "### Parent\n\n#### Child Header\n\nContent line.\n"
  end

  def test_emphasis_without_parent_header_becomes_h1
    original = <<~MD
      ---
      title: None
      ---

      _Standalone Section_
      Text under it.
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "# Standalone Section\n\nText under it.\n"
  end

  def test_emphasis_inside_code_block_is_ignored
    original = <<~MD
      ---
      title: Code Block
      ---

      ```
      **Not A Header**
      ```
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "```\n**Not A Header**\n```\n"
  end

  def test_repeated_emphasis_under_same_heading_does_not_nest_deeper
    original = <<~MD
      ---
      title: Multi Emphasis
      ---
      ## Header 2
      **emphasis 1**

      text 1

      **emphasis 2**
    MD

    result = @tidier.tidy_markdown(original)

    assert_includes result, "## Header 2\n\n### emphasis 1\n\ntext 1\n\n### emphasis 2\n"
  end
end
