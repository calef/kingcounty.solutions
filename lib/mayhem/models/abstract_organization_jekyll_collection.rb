# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'

module Mayhem
  module Models
    class AbstractOrganizationJekyllCollection < AbstractJekyllCollection
      def organization_title
        self['organization_title']
      end
    end
  end
end
