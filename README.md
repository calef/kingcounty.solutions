# kingcounty.solutions

Aggregates public service resources into a simple, searchable website to help people quickly find the support they need.

See `bin/README.md` and `script/README.md` for the automation helpers that handle data imports, audits, environment setup, and local preview workflows.

## Freezing imported entries

Automation can leave curated edits intact by setting `locked: true` in a post or event’s front matter. When this flag is present, the RSS/iCal importers, AI summarizers, and image extractor all skip the file entirely so the current body/front matter stay untouched while the rest of the pipeline continues to run.

## Sitemap

The `jekyll-sitemap` plugin is enabled so every build emits an up-to-date `sitemap.xml` at the site root for search engines and site audits.

## Tests

This repo uses Minitest for any Ruby automation or helpers. `bundle exec rake test` invokes `parallel_tests` so the suite runs across multiple workers. To run sequentially (for debugging), disable the parallel runner or pass `PARALLEL_TEST_PROCESSORS=1` before invoking the task:

```sh
bundle exec rake test
PARALLEL_TEST_PROCESSORS=1 bundle exec rake test
```

Run the integrity checks:

```sh
bin/mayhem check-integrity
RUN_EXPENSIVE_TESTS=true bin/mayhem check-integrity
```

`RUN_EXPENSIVE_TESTS` opts into the HTML5 validator; additional arguments (like `--name` or `--seed`) are passed straight through to Minitest.
