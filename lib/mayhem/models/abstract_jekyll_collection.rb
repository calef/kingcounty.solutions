# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class AbstractJekyllCollection < FMRepo::Record
      def published
        self['published']
      end

      def published?
        self['published'] != false
      end

      def title
        self['title']
      end
    end
  end
end
