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

    FileUtils.rm_rf(DESTINATION)
    config = Jekyll.configuration(
      'source' => Dir.pwd,
      'destination' => DESTINATION,
      'quiet' => true,
      'incremental' => false
    )

    Jekyll::Commands::Build.process(config)
    @site_built = true
  end
end
