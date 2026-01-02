# Separation Plan

## Overview

- Extract shared infrastructure (HTTP client stack, URL helpers, logging) into a new `seldon` repo so both Mayhem and Chio can depend on it.
- Create the `chio` repo to host the website-archive models (`AbstractSitemap`, `RobotsTxt`, `SitemapIndex`, `UrlSet`, `XmlSitemap`, `Website`), the refresh/generator services, and the new `chio` CLI (`create-website`, `refresh-websites`), plus their collection directories and tests.
- Remove the website-archive code and CLI commands from this Mayhem repo, updating remaining code to rely on `seldon` where needed.

## Step 1 – Build `seldon` *(completed)*

1. Inventory support/logging/utility classes under `lib/mayhem/support`, `lib/mayhem/logging`, and related helpers that both repos use.
2. Design a `seldon` gem API exposing equivalent modules (e.g., `Seldon::Support::HttpClient`, `Seldon::Logging`).
3. Create the new repo with its own `Gemfile`, FMRepo dependency if needed, and documentation for downstream usage.
4. Publish or reference `seldon` (via path/gem source) so Mayhem and later Chio can list it in their `Gemfile`s.

## Step 2 – Clean Mayhem & consume `seldon` (completed)

1. Update `Mayhem`’s `Gemfile` to depend on `seldon` (`gem 'seldon', git: 'git@github.com:calef/seldon.git'`) and remove the copied support files/logging code.
2. Ensure any remaining Mayhem code that relied on the copied helpers now requires `seldon` (e.g., `Mayhem::Robots::Refresh`, `Mayhem::Sitemaps::Refresh`, CLI command wrappers).
3. Document the consumption of `seldon` (update `bin/mayhem`, README, etc.) and verify the repo still builds/tests (`bundle exec jekyll build`, relevant test files).

## Step 3 – Create `chio`

1. Scaffold the `chio` repo (Ruby, FMRepo-backed) with collection dirs `_robots_txts`, `_sitemap_indexes`, `_url_sets`, `_websites`, `_xml_sitemaps`.
2. Move models and services tied to those collections from Mayhem (models + robots/sitemaps/websites generator/refresh).
3. Introduce the `chio` CLI with `create-website` and `refresh-websites`, wiring to the imported services.
4. Add tests moved from `test/mayhem/models`, `test/mayhem/robots`, `test/mayhem/sitemaps`, `test/mayhem/websites`, and update them to reference `seldon`.
5. Ensure `chio` depends on `seldon` for shared infrastructure and document usage.

## Step 4 – Remove `chio` pieces from Mayhem

1. Delete the models/services/tests tied to `_robots_txts`, `_sitemap_indexes`, `_url_sets`, `_websites`, `_xml_sitemaps` as well as the `create-website`/`refresh-websites` command handlers from `bin/mayhem`.
2. Update the remaining Mayhem tooling/docs to reflect that chio now owns website archive management.
3. Run any remaining relevant tests/builds to prove Mayhem is clean (`bundle exec jekyll build`, targeted minitest suites that still exist).

## Coordination

- Work in sequence steps 1 to 4. We will check in between each step.
- Keep the new repos referenced in this plan, update docs, and record verification steps for each.
