# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/image'

class ImageModelTest < Minitest::Test
  def test_creates_and_reads_images
    FMRepo::TestHelpers.with_temp_repo(role: :images) do
      record = Mayhem::Models::Image.create!(
        {
          'checksum' => 'abc123',
          'title' => 'Example Image',
          'image_url' => '/assets/images/abc123.webp',
          'organization_title' => 'Example',
          'source_url' => 'https://example.com/image',
          'date' => '2025-01-01T00:00:00Z'
        },
        body: 'Alt text'
      )

      assert_equal '_images/abc123.md', record.id
      assert_equal 'abc123', record.checksum
      assert_equal 'Example Image', record.title
      assert_equal '/assets/images/abc123.webp', record.image_url
      assert_equal 'Example', record.organization_title
      assert_equal 'https://example.com/image', record.source_url
      assert_equal '2025-01-01T00:00:00Z', record.date
      assert_equal 'Alt text', record.body.strip

      loaded = Mayhem::Models::Image.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Example Image', loaded.title
    end
  end
end
