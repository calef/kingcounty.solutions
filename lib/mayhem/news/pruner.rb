# frozen_string_literal: true

require_relative '../pruners/base'

module Mayhem
  module News
    class Pruner < Mayhem::Pruners::Base
      private

      def exclusion_key
        :excluded_post_ids
      end
    end
  end
end
