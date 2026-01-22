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

      def end_date
        self['end_date']
      end

      def end_date=(value)
        self['end_date'] = value
      end

      def generated_from_post
        self['generated_from_post']
      end

      def generated_from_post=(value)
        self['generated_from_post'] = value
      end

      def generated_from_post?
        self['generated_from_post'] == true
      end

      def location
        self['location']
      end

      def location=(value)
        self['location'] = value
      end

      def news
        require_relative 'news'
        News.find_by(source_url: source_url)
      end

      def start_date
        self['start_date']
      end

      def start_date=(value)
        self['start_date'] = value
      end
    end
  end
end
