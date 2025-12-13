# frozen_string_literal: true

require 'tmpdir'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/front_matter/document'

module Support
  class FrontMatterDocumentTest < Minitest::Test
    def test_load_reads_front_matter_and_body
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'sample.md')
        File.write(
          path,
          <<~MD
            ---
            title: Sample
            date: 2024-01-01
            ---
            Body text
          MD
        )

        doc = Mayhem::FrontMatter::Document.load(path)

        refute_nil doc
        assert_equal 'Sample', doc.front_matter['title']
        assert_includes doc.body, 'Body text'
      end
    end

    def test_save_produces_sorted_front_matter_and_blank_line
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'sorted.md')
        File.write(
          path,
          <<~MD
            ---
            zeta: last
            alpha: first
            ---
            Original
          MD
        )

        doc = Mayhem::FrontMatter::Document.load(path)
        doc['beta'] = 'middle'
        doc.body = 'Updated body'
        doc.save

        content = File.read(path)

        assert_match(/alpha: first\nbeta: middle\nzeta: last/, content)
        assert_match(/\n---\n\nUpdated body\n\z/, content)
      end
    end

    def test_load_returns_nil_for_missing_front_matter
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'sample.md')
        File.write(path, 'No front matter present')

        doc = Mayhem::FrontMatter::Document.load(path)

        assert_nil doc
      end
    end

    def test_build_markdown_inserts_blank_lines_around_headers
      body = <<~BODY
        First paragraph
        # Heading One
        Some detail
        ## Heading Two
        More detail
      BODY

      content = Mayhem::FrontMatter::Document.build_markdown({}, body)
      assert_includes content, "\n\n# Heading One\n\n"
      assert_includes content, "\n\n## Heading Two\n\n"
    end

    def test_build_markdown_inserts_blank_lines_around_lists
      body = <<~BODY
        Introduction
        - Item one
        - Item two
        Conclusion
      BODY

      content = Mayhem::FrontMatter::Document.build_markdown({}, body)
      assert_includes content, "Introduction\n\n- Item one"
      assert_includes content, "- Item two\n\nConclusion"
    end

    def test_build_markdown_appends_blank_line_after_list_at_end
      body = <<~BODY
        Section
        * First
        * Second
      BODY

      content = Mayhem::FrontMatter::Document.build_markdown({}, body)
      assert_match(/\* Second\n\n\z/, content)
    end
  end
end
