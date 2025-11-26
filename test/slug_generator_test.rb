# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/mayhem/support/slug_generator'

module Support
  class SlugGeneratorTest < Minitest::Test
    SlugGenerator = Mayhem::Support::SlugGenerator

    def test_sanitized_slug_downcases_and_strips_characters
      slug = SlugGenerator.sanitized_slug('Hello, World!')

      assert_equal 'hello-world', slug
    end

    def test_filename_slug_enforces_length
      slug = SlugGenerator.filename_slug(
        title: 'This is a very long title that should be truncated before writing to disk',
        link: 'https://example.com/item',
        date_prefix: '2024-05-01',
        max_bytes: 32
      )

      refute_includes slug, ' '
      assert_operator slug.bytesize, :<=, 32
    end
  end
end
