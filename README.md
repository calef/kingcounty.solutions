# kingcounty.solutions
Aggregates public service resources into a simple, searchable website to help people quickly find the support they need.

## Updating organization RSS feeds
`bin/update-news-rss` scans `_organizations/*.md` for records that have a `website` but no `news_rss_url`. For each match it:
1. Fetches the organization website with a desktop browser user agent.
2. Searches for `<link>` and `<a>` tags that reference RSS/Atom feeds (tries `/feed/` for WordPress sites too).
3. Validates the discovered URL actually responds with feed-like content.
4. Writes the `news_rss_url` into the document’s front matter (unless you run in dry-run mode).

### Usage
Run the script directly after `script/bootstrap` has installed dependencies:

```sh
bin/update-news-rss
```

You can narrow or preview the updates with environment variables:
- `TARGETS="solid-ground.md,attainhousing.md"` — only process the listed organization files (comma-separated, with or without `_organizations/`).
- `LIMIT=10` — stop after 10 processed organizations (useful when iterating).
- `DRY_RUN=1` — print findings without writing changes to disk.

Example dry run limited to a couple of orgs:

```sh
TARGETS="solid-ground.md,northwest-harvest.md" DRY_RUN=1 bin/update-news-rss
```

When you’re satisfied with the output, rerun without `DRY_RUN=1` so the script writes the `news_rss_url` values back to disk. Always follow up with `bundle exec jekyll build` (or `script/cibuild`) to make sure the new front matter is valid.
