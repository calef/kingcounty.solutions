# frozen_string_literal: true

require 'base64'
require 'pathname'
require 'time'
require 'uri'
require 'yaml'
require 'test_helper'

class ImageDocumentsTest < Minitest::Test
  REQUIRED_FIELDS = %w[checksum date image_url source source_url].freeze
  CHECKSUM_REGEX = /\A[0-9a-f]{64}\z/
  IMAGE_EXTENSIONS = %w[
    .avif .bmp .gif .heic .jpeg .jpg .png .svg .tif .tiff .webp
  ].freeze

  def setup
    @image_docs = Dir['_images/*.md'].map { |path| { path:, data: load_front_matter(path) } }
    @organization_titles = load_organization_titles
    @post_image_references = load_post_image_references
  end

  def test_required_fields_are_present
    errors = @image_docs.flat_map do |doc|
      missing = REQUIRED_FIELDS.reject { |field| present_string?(doc[:data][field]) }
      missing.map { |field| "#{relative_path(doc[:path])}: missing required field #{field}" }
    end

    assert_empty errors, errors.join("\n")
  end

  def test_checksum_format
    errors = @image_docs.filter_map do |doc|
      checksum = doc[:data]['checksum']
      next if checksum.is_a?(String) && checksum.match?(CHECKSUM_REGEX)

      "#{relative_path(doc[:path])}: checksum must be a 64-character hexadecimal string"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_date_parses_as_iso8601
    errors = @image_docs.filter_map do |doc|
      date = doc[:data]['date']
      begin
        Time.iso8601(date)
        nil
      rescue StandardError
        "#{relative_path(doc[:path])}: date must be an ISO8601 timestamp"
      end
    end

    assert_empty errors, errors.join("\n")
  end

  def test_image_url_points_to_local_image
    errors = @image_docs.filter_map do |doc|
      image_url = doc[:data]['image_url']
      next unless image_url

      relative_image_path = normalized_image_relative_path(image_url)
      unless relative_image_path
        next "#{relative_path(doc[:path])}: image_url #{image_url} must be an absolute path within the repository"
      end

      absolute_path = repo_root.join(relative_image_path).cleanpath
      unless path_within_repo?(absolute_path)
        next "#{relative_path(doc[:path])}: image_url #{image_url} must reference a file inside the repository"
      end

      unless absolute_path.file?
        next "#{relative_path(doc[:path])}: image_url #{image_url} does not exist at #{absolute_path.relative_path_from(repo_root)}"
      end

      next if IMAGE_EXTENSIONS.include?(absolute_path.extname.downcase)

      "#{relative_path(doc[:path])}: image_url #{image_url} must reference a known image extension"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_assets_images_have_metadata_documents
    asset_images = Dir['assets/images/**/*'].select do |path|
      File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
    end

    referenced_images = @image_docs.filter_map do |doc|
      image_url = doc[:data]['image_url']
      relative = normalized_image_relative_path(image_url)
      next unless relative

      relative_path(repo_root.join(relative))
    end.to_set

    errors = asset_images.filter_map do |path|
      relative = relative_path(path)
      next if referenced_images.include?(relative)

      "#{relative}: missing corresponding _images markdown document"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_source_matches_an_organization_title
    errors = @image_docs.filter_map do |doc|
      source = doc[:data]['source']
      next if source && @organization_titles.include?(source)

      "#{relative_path(doc[:path])}: source must match an organization title"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_source_url_points_is_valid_url
    errors = @image_docs.filter_map do |doc|
      source_url = doc[:data]['source_url']
      next unless source_url

      begin
        uri = URI.parse(source_url)
      rescue URI::InvalidURIError
        next "#{relative_path(doc[:path])}: source_url #{source_url} is not a valid URI"
      end

      unless %w[http https].include?(uri.scheme) && uri.host
        next "#{relative_path(doc[:path])}: source_url #{source_url} must be HTTP(S)"
      end
    end

    assert_empty errors, errors.join("\n")
  end

  def test_title_is_descriptive_when_present
    errors = @image_docs.filter_map do |doc|
      title = doc[:data]['title']
      next if title.nil?
      next if title.is_a?(String) && !title.strip.empty? && !title.match?(CHECKSUM_REGEX)

      "#{relative_path(doc[:path])}: title must be descriptive text when provided"
    end

    assert_empty errors, errors.join("\n")
  end

  def test_each_image_document_is_referenced_by_a_post
    errors = @image_docs.filter_map do |doc|
      checksum = doc[:data]['checksum']
      next unless checksum.is_a?(String)

      normalized = checksum.strip
      next if normalized.empty?

      posts = @post_image_references[normalized]
      next if posts && !posts.empty?

      "#{relative_path(doc[:path])}: expected at least one _posts/*.md to reference checksum #{normalized}"
    end

    assert_empty errors, errors.join("\n")
  end

  private

  def load_organization_titles
    Dir['_organizations/*.md'].filter_map do |path|
      data = load_front_matter(path)
      title = data['title']
      title if title.is_a?(String) && !title.strip.empty?
    end.to_set
  end

  def load_front_matter(path)
    lines = File.read(path).lines
    raise "#{path} missing front matter" unless lines.first&.strip == '---'

    yaml_lines = []
    lines[1..].each do |line|
      break if line.strip == '---'

      yaml_lines << line
    end

    YAML.safe_load(
      yaml_lines.join,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    ) || {}
  rescue Psych::SyntaxError => e
    flunk "#{path} has invalid YAML front matter: #{e.message}"
  end

  def load_post_image_references
    references_with_default = Hash.new { |hash, key| hash[key] = Set.new }
    Dir['_posts/*.md'].each do |path|
      data = load_front_matter(path)
      Array(data['images']).each do |checksum|
        next unless checksum.is_a?(String)

        normalized = checksum.strip
        next if normalized.empty?

        references_with_default[normalized] << relative_path(path)
      end
    end

    references_with_default.each_with_object({}) do |(checksum, posts), memo|
      memo[checksum] = posts
    end
  end

  def present_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end

  def relative_path(path)
    pn = Pathname.new(path)
    pn = repo_root.join(pn).cleanpath unless pn.absolute?
    pn.relative_path_from(repo_root).to_s
  rescue ArgumentError
    pn.to_s
  end

  def repo_root
    @repo_root ||= Pathname.new(Dir.pwd)
  end

  def normalized_image_relative_path(image_url)
    return unless image_url.is_a?(String)

    path = Pathname.new(image_url.strip)
    path = Pathname.new('/').join(path) unless path.absolute?
    clean = path.cleanpath
    return unless clean.to_s.start_with?('/')

    Pathname.new(clean.to_s.delete_prefix('/'))
  end

  def path_within_repo?(absolute_path)
    absolute_path.to_s.start_with?(repo_root.to_s + File::SEPARATOR) || absolute_path == repo_root
  end

end
