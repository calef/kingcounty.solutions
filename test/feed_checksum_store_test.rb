# frozen_string_literal: true

require 'tmpdir'
require_relative 'test_helper'
require_relative '../lib/mayhem/support/feed_checksum_store'

module Support
  class FeedChecksumStoreTest < Minitest::Test
    def test_persists_data
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'checksums.yml')
        store = Mayhem::Support::FeedChecksumStore.new(path:)
        store['http://example.com'] = 'abc'
        store.save

        reloaded = Mayhem::Support::FeedChecksumStore.new(path:)
        assert_equal 'abc', reloaded['http://example.com']
      end
    end
  end
end
