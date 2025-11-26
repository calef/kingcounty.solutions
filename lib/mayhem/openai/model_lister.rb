# frozen_string_literal: true

require 'ruby/openai'

module Mayhem
  module OpenAI
    class ModelLister
      def initialize(client: nil)
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      end

      def run
        response = @client.models.list
        response['data'].each do |model|
          puts model['id']
        end
      end
    end
  end
end
