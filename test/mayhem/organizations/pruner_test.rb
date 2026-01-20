# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'fmrepo'
require 'mayhem/organizations/pruner'
require 'mayhem/events/pruner'
require 'mayhem/news/pruner'
require 'mayhem/images/pruner'
require 'mayhem/models/event'
require 'mayhem/models/image'
require 'mayhem/models/news'
require 'mayhem/models/organization'
require 'seldon'
require 'tmpdir'

class OrganizationsPrunerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @org_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :organizations)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)
    @posts_dir = Mayhem::Models::News.collection_dir
    @events_dir = Mayhem::Models::Event.collection_dir
    @images_dir = Mayhem::Models::Image.collection_dir
    @assets_dir = File.join(Mayhem::Models::Image.repo.root.to_s, 'assets', 'images')
    @organizations_dir = Mayhem::Models::Organization.collection_dir
    FileUtils.mkdir_p([@posts_dir, @events_dir, @images_dir, @assets_dir, @organizations_dir])
    @logger = Seldon::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')

    @images_pruner = Mayhem::Images::Pruner.new

    @events_pruner = Mayhem::Events::Pruner.new(
      images_pruner: @images_pruner
    )

    @news_pruner = Mayhem::News::Pruner.new(
      images_pruner: @images_pruner
    )

    @pruner = Mayhem::Organizations::Pruner.new(
      events_pruner: @events_pruner,
      news_pruner: @news_pruner
    )
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
    @org_repo_override.cleanup if @org_repo_override
    @images_repo_override.cleanup if @images_repo_override
  end

  def test_prune_organization_content_removes_posts_and_events
    # Create content for target organization
    write_organization('Test Organization')
    write_post('post-1.md', 'Test Organization')
    write_post('post-2.md', 'Test Organization')
    write_event('event-1', 'Test Organization')

    # Create content for different organization
    write_organization('Other Organization')
    other_post_id = write_post('post-3.md', 'Other Organization')
    other_event_id = write_event('event-2', 'Other Organization')

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:events]
    assert_equal 2, result[:posts]
    assert result[:organization]

    # Verify target organization content is removed
    test_org = Mayhem::Models::Organization.all.to_a.find { |o| o['title'] == 'Test Organization' }
    assert_nil test_org
    test_posts = Mayhem::Models::News.all.select { |p| p['organization_title'] == 'Test Organization' }
    assert_empty test_posts
    test_events = Mayhem::Models::Event.all.select { |e| e['organization_title'] == 'Test Organization' }
    assert_empty test_events

    # Verify other organization content remains
    refute_nil Mayhem::Models::News.find(other_post_id)
    refute_nil Mayhem::Models::Event.find(other_event_id)
    other_org = Mayhem::Models::Organization.all.to_a.find { |o| o['title'] == 'Other Organization' }
    refute_nil other_org
  end

  def test_prune_organization_content_removes_images_from_posts
    image_id = 'test-image'
    write_image_metadata(image_id)
    write_asset(image_id)
    write_post('post-with-image.md', 'Test Organization', image_checksums: [image_id])

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:posts]
    test_posts = Mayhem::Models::News.all.select { |p| p['organization_title'] == 'Test Organization' }
    assert_empty test_posts
    assert_nil Mayhem::Models::Image.find_by(checksum: image_id)
    assert_empty Dir.glob(File.join(@assets_dir, "#{image_id}.*"))
  end

  def test_prune_organization_content_removes_event_links_from_posts
    event_id = write_event('event-1', 'Test Organization')
    post_id = write_post('post-with-event.md', 'Other Organization', event_ids: [event_id])

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:events]

    # Verify event link is removed from post
    updated_post = Mayhem::Models::News.find(post_id)
    assert_empty updated_post['event_ids']
  end

  def test_prune_organization_content_no_matches_returns_zero
    write_organization('Other Organization')
    other_post_id = write_post('post-1.md', 'Other Organization')
    other_event_id = write_event('event-1', 'Other Organization')

    result = @pruner.prune_organization_content('Nonexistent Organization')

    assert_equal 0, result[:events]
    assert_equal 0, result[:posts]
    refute result[:organization]

    # Verify content remains
    refute_nil Mayhem::Models::News.find(other_post_id)
    refute_nil Mayhem::Models::Event.find(other_event_id)
    other_org = Mayhem::Models::Organization.all.to_a.find { |o| o['title'] == 'Other Organization' }
    refute_nil other_org
  end

  private

  def write_organization(title)
    front_matter = {
      'title' => title,
      'type' => 'Community-Based Organization',
      'website' => 'https://example.com'
    }
    org = Mayhem::Models::Organization.create!(front_matter, body: 'Test organization')
    org.id
  end

  def write_post(filename, organization_title, image_checksums: [], event_ids: [])
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'organization_title' => organization_title,
      'source_url' => 'https://example.com',
      'image_checksums' => image_checksums,
      'event_ids' => event_ids,
      'published' => true
    }
    post = Mayhem::Models::News.create!(front_matter, body: '')
    post.id
  end

  def write_event(id, organization_title, image_checksums: [])
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => Time.now.utc.iso8601,
      'organization_title' => organization_title,
      'image_checksums' => image_checksums,
      'published' => true
    }
    event = Mayhem::Models::Event.create!(front_matter, body: '')
    event.id
  end

  def write_image_metadata(id)
    front_matter = {
      'checksum' => id,
      'image_url' => "/assets/images/#{id}.webp"
    }
    Mayhem::Models::Image.create!(front_matter, body: '')
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
