# frozen_string_literal: true

require 'test_helper'
require 'mayhem/openai/chat_client'

module Mayhem
  module OpenAI
    class ChatClientTest < Minitest::Test
      class FakeClient
        attr_reader :calls

        def initialize(response)
          @response = response
          @calls = []
        end

        def chat(parameters:)
          @calls << parameters
          @response
        end
      end

      def test_call_returns_sanitized_body
        client = FakeClient.new(
          'choices' => [
            { 'message' => { 'content' => "```json\nresults\n```" } }
          ]
        )

        chat_client = ChatClient.new(client: client)
        result = chat_client.call(
          messages: [{ role: 'user', content: 'hello' }],
          model: 'gpt-4o-mini',
          temperature: 0.5
        )

        assert_equal 'results', result
        assert_equal 1, client.calls.length
        parameters = client.calls.first
        assert_equal 'gpt-4o-mini', parameters[:model]
        assert_equal 0.5, parameters[:temperature]
      end

      def test_raises_when_openai_returns_error
        client = FakeClient.new('error' => { 'message' => 'boom' })
        chat_client = ChatClient.new(client: client)

        error = assert_raises RuntimeError do
          chat_client.call(
            messages: [{ role: 'user', content: 'hi' }],
            model: 'gpt-5.1'
          )
        end

        assert_match /LLM request failed/, error.message
      end

      def test_raises_when_no_content
        client = FakeClient.new('choices' => [{}])
        chat_client = ChatClient.new(client: client)

        assert_raises RuntimeError do
          chat_client.call(
            messages: [{ role: 'user', content: 'hi' }],
            model: 'gpt-5.1'
          )
        end
      end
    end
  end
end
