# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'pathname'
require 'nokogiri'
require 'nokogiri/html5'
require 'jekyll'
require 'jekyll/commands/build'

class SiteHtmlTest < Minitest::Test
  DESTINATION = File.expand_path('_site', Dir.pwd)

  def setup
    self.class.ensure_site_built
  end

  def test_generated_html_is_well_formed
    html_files = Dir.glob(File.join(DESTINATION, '**', '*.html'))
    refute_empty html_files, 'Expected jekyll build to produce HTML files'

    html_files.each do |path|
      document = Nokogiri::HTML5.parse(File.read(path))
      errors = document.errors
      assert errors.empty?, html_error_message(path, errors)
      refute_nil document.at('html'), "Missing <html> tag in #{relative_path(path)}"
    end
  end

  def self.ensure_site_built
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

  private

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(DESTINATION)).to_s
  end

  def html_error_message(path, errors)
    snippets = errors.first(3).map(&:message)
    <<~MSG
      HTML errors found in #{relative_path(path)}:
      - #{snippets.join("\n- ")}
    MSG
  end
end
