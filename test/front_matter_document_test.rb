# frozen_string_literal: true

require 'tmpdir'
require_relative 'test_helper'
require_relative '../lib/mayhem/support/front_matter_document'

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

        doc = Mayhem::Support::FrontMatterDocument.load(path)

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

        doc = Mayhem::Support::FrontMatterDocument.load(path)
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

        doc = Mayhem::Support::FrontMatterDocument.load(path)

        assert_nil doc
      end
    end
  end
end
