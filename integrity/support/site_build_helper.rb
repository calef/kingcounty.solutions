# frozen_string_literal: true

require 'fileutils'
require 'jekyll'
require 'jekyll/commands/build'

module SiteBuildHelper
  DESTINATION = File.expand_path('_site', Dir.pwd)

  module_function

  def destination
    DESTINATION
  end

  def ensure_site_built
    return if @site_built

    unless Dir.exist?(DESTINATION)
      raise(<<~MSG)
        Expected #{DESTINATION} to already contain a generated site.
        Run `./script/cibuild` (or `bundle exec jekyll build`) before running the tests.
      MSG
    end

    @site_built = true
  end
end
