# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/image'

class ImageModelTest < Minitest::Test
  def test_creates_and_reads_images
    FMRepo::TestHelpers.with_temp_repo(role: :images) do
      record = Mayhem::Models::Image.create!(
        {
          'checksum' => 'abc123',
          'date' => '2025-12-20T07:54:25+00:00',
          'image_url' => '/assets/images/abc123.webp',
          'source' => 'Test Source',
          'source_url' => 'https://example.com/image.png',
          'title' => 'Test Image'
        },
        body: ''
      )

      assert_equal '_images/abc123.md', record.id
      assert_equal 'abc123', record.checksum
      assert_equal '2025-12-20T07:54:25+00:00', record.date
      assert_equal '/assets/images/abc123.webp', record.image_url
      assert_equal 'Test Source', record.source
      assert_equal 'https://example.com/image.png', record.source_url
      assert_equal 'Test Image', record.title

      loaded = Mayhem::Models::Image.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test Image', loaded.title
      assert_equal 'abc123', loaded.checksum
    end
  end
end
