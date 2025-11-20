# kingcounty.solutions
Aggregates public service resources into a simple, searchable website to help people quickly find the support they need.

See `bin/README.md` and `script/README.md` for the automation helpers that handle data imports, audits, environment setup, and local preview workflows.

## Sitemap

The `jekyll-sitemap` plugin is enabled so every build emits an up-to-date `sitemap.xml` at the site root for search engines and site audits.

## Tests

This repo uses Minitest for any Ruby automation or helpers. Run the suite with:

```sh
bundle exec rake test
```
