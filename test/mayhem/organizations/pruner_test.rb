# frozen_string_literal: true

require 'fileutils'
require 'fmrepo'
require 'tmpdir'
require_relative '../../test_helper'
require 'mayhem/organizations/pruner'
require 'mayhem/events/pruner'
require 'mayhem/news/pruner'
require 'mayhem/images/pruner'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

class OrganizationsPrunerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('organizations-pruner')
    @posts_dir = File.join(@tmpdir, '_posts')
    @events_dir = File.join(@tmpdir, '_events')
    @images_dir = File.join(@tmpdir, '_images')
    @assets_dir = File.join(@tmpdir, 'assets', 'images')
    @organizations_dir = File.join(@tmpdir, '_organizations')
    FileUtils.mkdir_p([@posts_dir, @events_dir, @images_dir, @assets_dir, @organizations_dir])
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')

    @images_pruner = Mayhem::Images::Pruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      logger: @logger
    )

    @events_pruner = Mayhem::Events::Pruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_pruner: @images_pruner,
      logger: @logger
    )

    @news_pruner = Mayhem::News::Pruner.new(
      posts_dir: @posts_dir,
      images_pruner: @images_pruner,
      logger: @logger
    )

    @pruner = Mayhem::Organizations::Pruner.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      organizations_dir: @organizations_dir,
      events_pruner: @events_pruner,
      news_pruner: @news_pruner,
      logger: @logger
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_prune_organization_content_removes_posts_and_events
    # Create content for target organization
    write_organization('Test Organization')
    write_post('post-1.md', 'Test Organization')
    write_post('post-2.md', 'Test Organization')
    write_event('event-1', 'Test Organization')

    # Create content for different organization
    write_organization('Other Organization')
    write_post('post-3.md', 'Other Organization')
    write_event('event-2', 'Other Organization')

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:events]
    assert_equal 2, result[:posts]
    assert result[:organization]

    # Verify target organization content is removed
    refute_path_exists File.join(@posts_dir, 'post-1.md')
    refute_path_exists File.join(@posts_dir, 'post-2.md')
    refute_path_exists File.join(@events_dir, 'event-1.md')
    refute_path_exists File.join(@organizations_dir, 'test-organization.md')

    # Verify other organization content remains
    assert_path_exists File.join(@posts_dir, 'post-3.md')
    assert_path_exists File.join(@events_dir, 'event-2.md')
    assert_path_exists File.join(@organizations_dir, 'other-organization.md')
  end

  def test_prune_organization_content_removes_images_from_posts
    image_id = 'test-image'
    write_image_metadata(image_id)
    write_asset(image_id)
    write_post('post-with-image.md', 'Test Organization', images: [image_id])

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:posts]
    refute_path_exists File.join(@posts_dir, 'post-with-image.md')
    refute_path_exists File.join(@images_dir, "#{image_id}.md")
    assert_empty Dir.glob(File.join(@assets_dir, "#{image_id}.*"))
  end

  def test_prune_organization_content_removes_event_links_from_posts
    write_event('event-1', 'Test Organization')
    write_post('post-with-event.md', 'Other Organization', events: ['event-1'])

    result = @pruner.prune_organization_content('Test Organization')

    assert_equal 1, result[:events]

    # Verify event link is removed from post
    updated_post = Mayhem::FrontMatter::Document.load(File.join(@posts_dir, 'post-with-event.md'))
    assert_empty updated_post.front_matter['events']
  end

  def test_prune_organization_content_no_matches_returns_zero
    write_organization('Other Organization')
    write_post('post-1.md', 'Other Organization')
    write_event('event-1', 'Other Organization')

    result = @pruner.prune_organization_content('Nonexistent Organization')

    assert_equal 0, result[:events]
    assert_equal 0, result[:posts]
    refute result[:organization]

    # Verify content remains
    assert_path_exists File.join(@posts_dir, 'post-1.md')
    assert_path_exists File.join(@events_dir, 'event-1.md')
    assert_path_exists File.join(@organizations_dir, 'other-organization.md')
  end

  private

  def write_organization(title)
    slug = FMRepo.slugify(title)
    front_matter = {
      'title' => title,
      'type' => 'Community-Based Organization',
      'website' => 'https://example.com'
    }
    path = File.join(@organizations_dir, "#{slug}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, 'Test organization'))
    path
  end

  def write_post(filename, source, images: [], events: [])
    front_matter = {
      'title' => 'Test Post',
      'date' => Time.now.utc.iso8601,
      'source' => source,
      'source_url' => 'https://example.com',
      'images' => images,
      'events' => events,
      'published' => true
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_event(id, organization_title, images: [])
    path = File.join(@events_dir, "#{id}.md")
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => Time.now.utc.iso8601,
      'organization_title' => organization_title,
      'images' => images,
      'published' => true
    }
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_image_metadata(id)
    File.write(File.join(@images_dir, "#{id}.md"), "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
