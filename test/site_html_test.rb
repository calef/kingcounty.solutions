# frozen_string_literal: true

require 'test_helper'
require 'pathname'
require 'nokogiri'
require 'nokogiri/html5'
require_relative 'support/site_build_helper'

class SiteHtmlTest < Minitest::Test
  def setup
    SiteBuildHelper.ensure_site_built
  end

  def test_generated_html_is_well_formed
    destination = SiteBuildHelper.destination
    html_files = Dir.glob(File.join(destination, '**', '*.html'))

    refute_empty html_files, 'Expected jekyll build to produce HTML files'

    html_files.each do |path|
      document = Nokogiri::HTML5.parse(File.read(path))
      errors = document.errors

      assert_empty errors, html_error_message(path, errors)
      refute_nil document.at('html'), "Missing <html> tag in #{relative_path(path)}"
    end
  end

  private

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(SiteBuildHelper.destination)).to_s
  end

  def html_error_message(path, errors)
    snippets = errors.first(3).map(&:message)
    <<~MSG
      HTML errors found in #{relative_path(path)}:
      - #{snippets.join("\n- ")}
    MSG
  end
end
