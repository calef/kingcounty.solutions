# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/topics/classifier'

module Mayhem
  module Topics
    class ClassifierTest < Minitest::Test
      class FakeClient
        attr_reader :call_count, :last_parameters

        def initialize(response)
          @response = response
          @call_count = 0
          @last_parameters = []
        end

        def chat(parameters:)
          @call_count += 1
          @last_parameters << parameters
          @response
        end
      end

      def setup
        @temp_dir = Dir.mktmpdir('topic_catalog')
        @repo = FMRepo::Repository.new(root: @temp_dir)
      end

      def teardown
        FileUtils.remove_entry(@temp_dir)
      end

      def test_classifies_text_against_catalog
        create_topic('Housing', 'Updates about affordable housing and shelter programs.')
        create_topic('Food', 'Community meals and nutrition support.')

        client = FakeClient.new(
          'choices' => [
            { 'message' => { 'content' => '["Food"]' } }
          ]
        )

        classifier = Classifier.new(topic_repo: @repo, client: client)

        assert_equal ['Food'], classifier.classify('A weekly recap mentions community meals and food assistance.')
        assert_equal 1, client.call_count
      end

      def test_returns_empty_when_text_blank
        create_topic('Safety', 'Articles about safety nets.')
        client = FakeClient.new('choices' => [{ 'message' => { 'content' => '["Safety"]' } }])
        classifier = Classifier.new(topic_repo: @repo, client: client)

        assert_empty classifier.classify('   ')
        assert_equal 0, client.call_count
      end

      def test_returns_empty_when_no_topics_available
        client = FakeClient.new('choices' => [{ 'message' => { 'content' => '["Safety"]' } }])
        classifier = Classifier.new(topic_repo: @repo, client: client)

        assert_empty classifier.classify('New content about safety.')
        assert_equal 0, client.call_count
      end

      private

      def create_topic(title, summary)
        Mayhem::Models::Topic.create!(
          { 'title' => title },
          body: summary,
          repo: @repo
        )
      end
    end
  end
end
