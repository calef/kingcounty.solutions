# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jekyll-based static site aggregating public service resources for King County, WA. Two-layer architecture:

1. **Jekyll static site** - Collections in `_organizations/`, `_locations/`, `_topics/`, `_events/`, `_posts/`, `_images/`
2. **Mayhem automation** - Ruby library in `lib/mayhem/` handling content imports, AI summarization, image extraction

Over time, we are separating these two components into separate repos.

## Build & Test Commands

```bash
# Setup
./script/bootstrap

# Run all tests (parallel by default)
bundle exec rake test

# Run tests sequentially (for debugging)
PARALLEL_TEST_PROCESSORS=1 bundle exec rake test

# Run a single test file
ruby -Ilib:test test/mayhem/news/rss_importer_test.rb

# Run a single test method
ruby -Ilib:test test/mayhem/news/rss_importer_test.rb -n RssImporterTest::test_creates_post

# Local development server
./script/server

# CI build + tests
./script/cibuild

# Integrity checks
bin/mayhem check-integrity
RUN_EXPENSIVE_TESTS=true bin/mayhem check-integrity
```

## Key Mayhem Commands

```bash
bin/mayhem import-content      # RSS + iCal imports
bin/mayhem summarize           # AI summaries + topic classification
bin/mayhem extract-events      # Extract events from news posts
bin/mayhem extract-images      # Download and process images
bin/mayhem expire              # Delete old content
bin/mayhem ingest              # Full pipeline (all above in order)
bin/mayhem check-source-urls   # Validate/prune dead links
bin/mayhem tidy _posts/        # Normalize front matter
```

Requires `OPENAI_API_KEY` for AI commands.

## Architecture

### Content Models (`lib/mayhem/models/`)

Uses FMRepo gem for file-based persistence. Models inherit from `AbstractJekyllCollection`:

```ruby
# Usage pattern
post = Mayhem::Models::News.find("_posts/2025-01-20-example.md")
Mayhem::Models::Event.all.each { |e| e.save! }
```

### Key Modules

- `lib/mayhem/news/` - RSS import (`RssImporter`), summarization, pruning
- `lib/mayhem/events/` - iCal import (`IcalImporter`), summarization, cleanup
- `lib/mayhem/images/` - Image extraction, WebP conversion, pruning
- `lib/mayhem/content/` - Article body extraction, HTML normalization, URL checking
- `lib/mayhem/front_matter/` - YAML front matter manipulation (`Tidier`)

**Important**: The `FrontMatter::Document` class is deprecated. Use `Mayhem::Models::*` classes (News, Event, Organization, Image, Topic, Location) instead. These models provide the same functionality with proper FMRepo integration.

### Content Freezing

Set `locked: true` in front matter to prevent automation from modifying a file. All importers, summarizers, and extractors respect this flag.

## Code Style

- 2-space indentation
- `frozen_string_literal: true` at top of Ruby files
- YAML keys: lowercase snake_case, sorted alphabetically
- Files: kebab-case (e.g., `auburn.md`)
- Rubocop enforced: `bundle exec rubocop -A`

## Testing Patterns

- **Framework**: Minitest
- **HTTP mocking**: VCR cassettes in `test/mayhem/vcr_cassettes/`
- **File I/O**: `FMRepo::TestHelpers.with_temp_repo(role: :news)` for temp repos

To re-record a VCR cassette, delete the YAML file and re-run the test.

## Environment Variables

| Variable | Purpose |
| ---------- | --------- |
| `OPENAI_API_KEY` | Required for AI commands |
| `OPENAI_MODEL` | Default model (gpt-4o-mini) |
| `LOG_LEVEL` | TRACE/DEBUG/INFO/WARN/ERROR/FATAL |
| `RSS_WORKERS` | Thread count for RSS import (default 6) |
| `ICAL_WORKERS` | Thread count for iCal import (default 6) |
