# frozen_string_literal: true

require 'pathname'
require 'test_helper'
require_relative 'support/site_build_helper'

class FrontMatterStructureTest < Minitest::Test
  DELIMITER = /\A---\s*\z/

  def setup
    @site = load_site
    @source_root = Pathname.new(@site.source)
  end

  def test_markdown_documents_have_single_front_matter
    errors = markdown_entry_paths(@site).filter_map { |path| front_matter_error(path) }

    assert_empty errors, "Front matter issues detected:\n#{errors.join("\n")}"
  end

  private

  attr_reader :site, :source_root

  def load_site
    config = Jekyll.configuration(
      'source' => Dir.pwd,
      'destination' => SiteBuildHelper.destination,
      'quiet' => true,
      'incremental' => false
    )
    site = Jekyll::Site.new(config)
    site.reset
    site.read
    site
  end

  def markdown_entry_paths(site)
    extensions = markdown_extensions(site)
    docs = site.pages + site.collections.values.flat_map(&:docs)
    doc_paths = docs
                .map(&:path)
                .select { |path| extensions.include?(File.extname(path).downcase) }

    static_paths = site.static_files
                       .map(&:path)
                       .select { |path| extensions.include?(File.extname(path).downcase) }

    (doc_paths + static_paths).map { |path| absolute_path(path) }.uniq
  end

  def markdown_extensions(site)
    ext_list = site.config.fetch('markdown_ext', 'markdown,mkdown,mkdn,mkd,md')
    ext_list.split(',').map { |ext| ".#{ext.strip.downcase}" }
  end

  def front_matter_error(path)
    return "#{relative_path(path)}: file does not exist" unless File.exist?(path)

    lines = File.read(path).split(/\r?\n/)
    return "#{relative_path(path)}: missing front matter opening ---" unless lines.first&.match?(DELIMITER)

    closing_offset = lines.drop(1).index { |line| line.match?(DELIMITER) }
    return "#{relative_path(path)}: missing front matter closing ---" unless closing_offset

    closing_index = closing_offset + 1
    front_matter_lines = lines[1...closing_index]
    unless front_matter_lines&.any? { |line| !line.strip.empty? }
      return "#{relative_path(path)}: empty front matter block"
    end

    nil
  end

  def absolute_path(path)
    pathname = Pathname.new(path)
    pathname.absolute? ? pathname : source_root.join(pathname)
  end

  def relative_path(path)
    path = Pathname.new(path)
    path.relative_path_from(source_root).to_s
  end
end
