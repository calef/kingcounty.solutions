# frozen_string_literal: true

require 'tmpdir'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/front_matter/publish_guard'

module Support
  class PublishGuardTest < Minitest::Test
    PublishGuard = Mayhem::FrontMatter::PublishGuard

    def teardown
      Mayhem::Logging.reset_logger
    end

    def test_unpublished_returns_true_when_flagged_false
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'hidden.md')
        File.write(
          path,
          <<~MD
            ---
            title: Hidden
            published: false
            ---
            Secret
          MD
        )

        assert PublishGuard.unpublished?(path)
      end
    end

    def test_unpublished_returns_false_for_missing_file
      Dir.mktmpdir do |dir|
        missing_path = File.join(dir, 'does-not-exist.md')

        refute PublishGuard.unpublished?(missing_path)
      end
    end

    def test_unpublished_returns_false_when_not_explicitly_hidden
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'visible.md')
        File.write(
          path,
          <<~MD
            ---
            title: Visible
            ---
            Body
          MD
        )

        refute PublishGuard.unpublished?(path)
      end
    end

    def test_unpublished_warns_and_returns_false_when_inspection_fails
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'error.md')
        File.write(
          path,
          <<~MD
            ---
            title: Error
            ---
            Broken
          MD
        )

        logger = Minitest::Mock.new
        logger.expect(:warn, nil, [String])

        stub = lambda do |_path, **_kwargs|
          raise StandardError, 'boom'
        end

        Mayhem::Logging.logger = logger

        Mayhem::FrontMatter::Document.stub(:load, stub) do
          refute PublishGuard.unpublished?(path)
        end

        logger.verify
      end
    end
  end
end
