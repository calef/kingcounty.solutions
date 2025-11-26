# kingcounty.solutions
Aggregates public service resources into a simple, searchable website to help people quickly find the support they need.

See `bin/README.md` and `script/README.md` for the automation helpers that handle data imports, audits, environment setup, and local preview workflows.

## Sitemap

The `jekyll-sitemap` plugin is enabled so every build emits an up-to-date `sitemap.xml` at the site root for search engines and site audits.

## Tests

This repo uses Minitest for any Ruby automation or helpers. `bundle exec rake test` now invokes `parallel_tests` when the gem is installed so the suite runs across multiple workers; it falls back to the legacy `rake test` task when the gem is missing. The HTML/JSON/JS assertions simply read files from `_site`, so make sure you generate the site first (e.g., `./script/cibuild` already runs before the suite in CI). To run sequentially (for debugging), disable the parallel runner or pass `PARALLEL_TEST_PROCESSORS=1` before invoking the task:

```sh
bundle exec rake test
PARALLEL_TEST_PROCESSORS=1 bundle exec rake test
```
