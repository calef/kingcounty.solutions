# Copilot Instructions

## Project Overview

This is a Jekyll-based static site that aggregates public service resources into a searchable website for King County, WA. The site helps people find support services, information about local organizations, and community resources.

## Project Structure

- Jekyll sources live at the repo root
- `_layouts`, `_includes`, and `_sass` control shared markup
- Collections are in `_organizations`, `_places`, and `_topics`
- `_posts` holds imported news
- Assets are under `assets/` (CSS/JS, favicons)
- Generated output lands in `_site/` (ignored by Git)
- Utility scripts in `bin/` and `script/` automate importing RSS feeds, updating schemas, and toolchain setup

## Build and Development Commands

- `script/bootstrap` — preferred entry point; installs Ruby/Bundler via mise helpers and runs `bundle install`
- `script/server` — wraps `bundle exec jekyll serve --livereload` for preview at `http://127.0.0.1:4000`
- `script/cibuild` — invokes `bundle exec jekyll build` plus CI checks; run locally before PRs
- `bundle exec rake test` — runs the Minitest test suite

## Coding Style

- Use two spaces for indentation in Liquid templates, Markdown front matter, and Ruby scripts
- Keep YAML keys lowercase with snake_case (e.g., `parent_place`)
- Name files with kebab-case (e.g., `places.md`)
- Keep collection documents singular (`title: Auburn`, filename `auburn.md`)
- Use concise inline comments only when necessary to explain non-obvious logic
- Sort frontmatter keys alphabetically

## Testing

- Run `bundle exec jekyll build` after structural changes to catch Liquid or front-matter errors
- Run `bundle exec rake test` to execute the Minitest test suite
- Tests use VCR cassettes under `test/vcr_cassettes/` for HTTP interactions

## Commit Guidelines

- Follow imperative, concise commit messages (e.g., `Add places hierarchy layout`, `Fix RSS importer skip logic`)
- Keep diffs focused; split refactors from feature work when practical
- Never commit `_site/` artifacts or local caches
