# frozen_string_literal: true

module Mayhem
  module Models
    module Concerns
      # Provides class macros for defining front matter attribute accessors.
      #
      # @example Simple accessor
      #   fm_accessor :title, :date
      #   # Creates: title, title=, date, date=
      #
      # @example Accessor with default value
      #   fm_accessor :tags, default: []
      #   # Creates: tags (returns [] if nil), tags=
      #
      # @example Boolean accessor
      #   fm_boolean :published, default: true
      #   # Creates: published, published=, published? (returns true unless explicitly false)
      #
      # @example Boolean accessor with false default
      #   fm_boolean :locked
      #   # Creates: locked, locked=, locked? (returns true only if explicitly true)
      module FrontMatterAccessors
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Defines getter and setter methods for front matter attributes.
          #
          # @param names [Array<Symbol>] attribute names
          # @param default [Object, nil] default value for getter when attribute is nil
          def fm_accessor(*names, default: nil)
            names.each do |name|
              key = name.to_s

              if default.nil?
                define_method(name) { self[key] }
              else
                define_method(name) { self[key].nil? ? default : self[key] }
              end

              define_method(:"#{name}=") { |value| self[key] = value }
            end
          end

          # Defines getter, setter, and predicate methods for boolean front matter attributes.
          #
          # @param name [Symbol] attribute name
          # @param default [Boolean] if true, predicate returns true unless explicitly false;
          #   if false (default), predicate returns true only if explicitly true
          def fm_boolean(name, default: false)
            key = name.to_s

            define_method(name) { self[key] }
            define_method(:"#{name}=") { |value| self[key] = value }

            if default
              # Default true: returns true unless explicitly false
              define_method(:"#{name}?") { self[key] != false }
            else
              # Default false: returns true only if explicitly true
              define_method(:"#{name}?") { self[key] == true }
            end
          end
        end
      end
    end
  end
end
