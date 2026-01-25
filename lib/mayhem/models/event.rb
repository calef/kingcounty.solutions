# frozen_string_literal: true

require 'date'
require 'fmrepo'
require_relative 'abstract_content'

module Mayhem
  module Models
    class Event < AbstractContent
      repository_role :events
      scope glob: '_events/**/*.md'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        prefix = begin
          value = front_matter['start_date'].to_s.strip
          value.empty? ? nil : Date.parse(value).strftime('%Y-%m-%d')
        rescue StandardError
          nil
        end
        name = prefix ? "#{prefix}-#{slug}" : slug
        "_events/#{name}.md"
      end

      fm_accessor :end_date, :location, :start_date
      fm_boolean :generated_from_post

      # Returns the News record that shares this event's source_url.
      # Returns nil if no matching news post is found.
      def news
        require_relative 'news'
        News.find_by(source_url: source_url)
      end
    end
  end
end
