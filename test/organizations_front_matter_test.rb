# frozen_string_literal: true

require 'set'
require 'uri'
require 'yaml'
require 'test_helper'

class OrganizationsFrontMatterTest < Minitest::Test
  ALLOWED_FIELDS = %w[
    acronym
    address
    email
    events_ical_url
    jurisdictions
    news_rss_url
    parent_organization
    phone
    title
    topics
    type
    website
  ].freeze
  ALLOWED_TYPES = [
    'Agency',
    'City',
    'College',
    'Community-Based Organization',
    'Corporation',
    'Country',
    'County',
    'Department',
    'Division',
    'Independent Federal Agency',
    'Independent Public Corporation',
    'Program',
    'Public Hospital District',
    'School District',
    'Special Purpose District',
    'State',
    'Town',
    'Tribe',
    'University'
  ].freeze
  STATE_NAMES = [
    'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado', 'Connecticut',
    'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa',
    'Kansas', 'Kentucky', 'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan',
    'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
    'New Hampshire', 'New Jersey', 'New Mexico', 'New York', 'North Carolina',
    'North Dakota', 'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island',
    'South Carolina', 'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont',
    'Virginia', 'Washington', 'West Virginia', 'Wisconsin', 'Wyoming', 'District of Columbia'
  ].freeze
  STATE_ABBREVIATIONS = %w[
    AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN
    MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT
    VA WA WV WI WY DC
  ].freeze
  STATE_NAME_REGEX = Regexp.union(STATE_NAMES.map { |name| /\b#{Regexp.escape(name)}\b/i })
  STATE_ABBREVIATION_REGEX = /\b(?:#{STATE_ABBREVIATIONS.join('|')})\b/i
  TYPE_WORD = /[A-Z][A-Za-z]*(?:-[A-Z][A-Za-z]*)*/
  TYPE_PATTERN = /\A#{TYPE_WORD}(?: (?:& )?#{TYPE_WORD})*\z/

  def setup
    @organizations = load_documents('_organizations/*.md')
    @organization_titles = @organizations.map { |doc| doc[:data]['title'] }.compact
    @places = load_titles('_places/*.md')
    @topics = load_titles('_topics/*.md')
  end

  def test_documents_only_use_allowed_fields
    errors = []

    organizations.each do |doc|
      next unless doc[:data]

      extra_fields = doc[:data].keys - ALLOWED_FIELDS
      next if extra_fields.empty?

      errors << "#{doc[:path]} has unsupported fields: #{extra_fields.join(', ')}"
    end

    assert errors.empty?, "Unexpected front matter fields:\n#{errors.join("\n")}"
  end

  def test_title_is_present_and_unique
    errors = []
    seen = Hash.new { |hash, key| hash[key] = [] }

    organizations.each do |doc|
      title = value_as_string(doc, 'title')
      if title.nil? || title.strip.empty?
        errors << "#{doc[:path]} missing required title"
        next
      end
      seen[title.strip] << doc[:path]
    end

    seen.each do |title, paths|
      next if paths.one?

      errors << "title '#{title}' appears in #{paths.join(', ')}"
    end

    assert errors.empty?, "Title issues:\n#{errors.join("\n")}"
  end

  def test_website_is_present_valid_and_unique
    errors = []
    seen = {}

    organizations.each do |doc|
      website = value_as_string(doc, 'website')
      if website.nil? || website.empty?
        errors << "#{doc[:path]} missing required website"
        next
      end
      unless valid_url?(website)
        errors << "#{doc[:path]} has invalid website URL: #{website}"
      end

      normalized = website.strip.downcase
      if seen.key?(normalized)
        errors << "website #{website} reused in #{doc[:path]} and #{seen[normalized]}"
      else
        seen[normalized] = doc[:path]
      end
    end

    assert errors.empty?, "Website issues:\n#{errors.join("\n")}"
  end

  def test_acronym_if_present_is_uppercase_abbreviation
    errors = []

    organizations.each do |doc|
      acronym = value_as_string(doc, 'acronym')
      next if acronym.nil?

      unless acronym.match?(/\A[A-Z0-9][A-Z0-9.&()\/-]*(?: [A-Z0-9][A-Z0-9.&()\/-]*)*\z/)
        errors << "#{doc[:path]} acronym '#{acronym}' is not an uppercase abbreviation"
      end

      title = value_as_string(doc, 'title')
      next unless title
      if acronym.length >= title.length
        errors << "#{doc[:path]} acronym '#{acronym}' should be shorter than the title '#{title}'"
      end
    end

    assert errors.empty?, "Acronym issues:\n#{errors.join("\n")}"
  end

  def test_address_if_present_resembles_usable_us_address
    errors = []

    organizations.each do |doc|
      address = value_as_string(doc, 'address')
      next if address.nil?

      unless valid_street_address?(address)
        errors << "#{doc[:path]} address '#{address}' must be a mailable US street address"
      end
    end

    assert errors.empty?, "Address issues:\n#{errors.join("\n")}"
  end

  def test_email_if_present_is_unique_and_valid
    errors = []
    seen = {}

    organizations.each do |doc|
      email = value_as_string(doc, 'email')
      next if email.nil?

      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        errors << "#{doc[:path]} email '#{email}' is not a valid address"
      end

      normalized = email.downcase
      if seen.key?(normalized)
        errors << "email #{email} reused in #{doc[:path]} and #{seen[normalized]}"
      else
        seen[normalized] = doc[:path]
      end
    end

    assert errors.empty?, "Email issues:\n#{errors.join("\n")}"
  end

  def test_events_ical_url_if_present_is_valid_and_unique
    errors = []
    seen = {}

    organizations.each do |doc|
      url = value_as_string(doc, 'events_ical_url')
      next if url.nil?

      unless valid_url?(url)
        errors << "#{doc[:path]} events_ical_url '#{url}' is not a valid URL"
      end

      normalized = url.strip.downcase
      if seen.key?(normalized)
        errors << "events_ical_url #{url} reused in #{doc[:path]} and #{seen[normalized]}"
      else
        seen[normalized] = doc[:path]
      end
    end

    assert errors.empty?, "events_ical_url issues:\n#{errors.join("\n")}"
  end

  def test_jurisdictions_are_present_and_reference_known_places
    errors = []

    organizations.each do |doc|
      jurisdictions = doc[:data]['jurisdictions']
      if !jurisdictions.is_a?(Array) || jurisdictions.empty?
        errors << "#{doc[:path]} requires jurisdictions list"
        next
      end

      jurisdictions.each do |jurisdiction|
        unless places.include?(jurisdiction)
          errors << "#{doc[:path]} jurisdiction '#{jurisdiction}' is not a known place"
        end
      end
    end

    assert errors.empty?, "Jurisdiction issues:\n#{errors.join("\n")}"
  end

  def test_news_rss_url_if_present_is_valid
    errors = []

    organizations.each do |doc|
      url = value_as_string(doc, 'news_rss_url')
      next if url.nil?

      errors << "#{doc[:path]} news_rss_url '#{url}' is not a valid URL" unless valid_url?(url)
    end

    assert errors.empty?, "news_rss_url issues:\n#{errors.join("\n")}"
  end

  def test_parent_organization_if_present_matches_existing_title
    errors = []

    organizations.each do |doc|
      parent = value_as_string(doc, 'parent_organization')
      next if parent.nil?

      unless organization_titles.include?(parent)
        errors << "#{doc[:path]} parent_organization '#{parent}' does not match another organization title"
        next
      end

      title = value_as_string(doc, 'title')
      if title && title == parent
        errors << "#{doc[:path]} parent_organization must not reference itself"
      end
    end

    assert errors.empty?, "parent_organization issues:\n#{errors.join("\n")}"
  end

  def test_phone_if_present_is_unique_and_resembles_number
    errors = []
    seen = {}

    organizations.each do |doc|
      phone = value_as_string(doc, 'phone')
      next if phone.nil?

      unless phone.match?(/\d/)
        errors << "#{doc[:path]} phone '#{phone}' must contain digits"
      end

      unless phone.match?(/\A[0-9A-Za-z+().\-\s\/]*?(?:ext[:.]?\s?\d+|x\d+)?\z/)
        errors << "#{doc[:path]} phone '#{phone}' contains unsupported characters"
      end

      normalized = phone.gsub(/[^0-9A-Za-z]/, '').downcase
      next if normalized.empty?

      if seen.key?(normalized)
        errors << "phone #{phone} reused in #{doc[:path]} and #{seen[normalized]}"
      else
        seen[normalized] = doc[:path]
      end
    end

    assert errors.empty?, "Phone issues:\n#{errors.join("\n")}"
  end

  def test_topics_if_present_reference_known_topics
    errors = []

    organizations.each do |doc|
      topics_value = doc[:data]['topics']
      next if topics_value.nil?
      unless topics_value.is_a?(Array) && topics_value.all? { |topic| topic.is_a?(String) }
        errors << "#{doc[:path]} topics must be a list of strings"
        next
      end

      topics_value.each do |topic|
        errors << "#{doc[:path]} topic '#{topic}' is not defined" unless topics.include?(topic)
      end
    end

    assert errors.empty?, "Topic issues:\n#{errors.join("\n")}"
  end

  def test_type_is_present_and_capitalized_words
    errors = []

    organizations.each do |doc|
      type = value_as_string(doc, 'type')
      if type.nil? || type.empty?
        errors << "#{doc[:path]} missing required type"
        next
      end

      errors << "#{doc[:path]} type '#{type}' must be capitalized words" unless type.match?(TYPE_PATTERN)
    end

    assert errors.empty?, "Type issues:\n#{errors.join("\n")}"
  end

  def test_type_is_an_allowed_value
    errors = []

    organizations.each do |doc|
      type = value_as_string(doc, 'type')
      next if type.nil?
      next if ALLOWED_TYPES.include?(type)

      errors << "#{doc[:path]} type '#{type}' is not in the allowed list: #{ALLOWED_TYPES.join(', ')}"
    end

    assert errors.empty?, "Type whitelist issues:\n#{errors.join("\n")}"
  end

  def test_events_ical_url_news_rss_url_and_website_are_http_or_https
    errors = []
    fields = %w[events_ical_url news_rss_url website]

    organizations.each do |doc|
      fields.each do |field|
        url = value_as_string(doc, field)
        next if url.nil?
        uri = parse_uri(url)
        next if uri && %w[http https].include?(uri.scheme)

        errors << "#{doc[:path]} #{field} '#{url}' must be an http(s) URL"
      end
    end

    assert errors.empty?, "URL scheme issues:\n#{errors.join("\n")}"
  end

  private

  attr_reader :organizations, :organization_titles, :places, :topics

  def load_documents(glob)
    Dir[glob].sort.map do |path|
      { path: path, data: read_front_matter(path) }
    end
  end

  def load_titles(glob)
    Dir[glob].each_with_object(Set.new) do |path, titles|
      data = read_front_matter(path)
      next unless data

      title = data['title']
      titles << title if title
    end
  end

  def read_front_matter(path)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*/m)
    return {} unless match

    YAML.safe_load(match[1], permitted_classes: [], aliases: true) || {}
  end

  def value_as_string(doc, field)
    value = doc[:data][field]
    return unless value

    value.is_a?(String) ? value.strip : nil
  end

  def valid_url?(value)
    uri = parse_uri(value)
    uri && uri.host && %w[http https].include?(uri.scheme)
  end

  def parse_uri(value)
    URI.parse(value)
  rescue URI::InvalidURIError
    nil
  end

  def valid_street_address?(value)
    return false unless value.match?(/\d/)
    has_state = value.match?(STATE_ABBREVIATION_REGEX) || value.match?(STATE_NAME_REGEX)
    has_zip = value.match?(/\b\d{5}(?:-\d{4})?\b/)
    has_city_separator = value.include?(',')

    has_state && has_city_separator && has_zip
  end
end
