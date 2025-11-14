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

## Weekly roundup generator
`bin/generate-weekly-summary` assembles the previous Sunday–Saturday `_posts/` entries into a single “King County Solutions Weekly Roundup” article.

- Pass 1 (theme planning): sends the week’s metadata to OpenAI to cluster posts into 3–4 themes and pick spotlight candidates.
- Pass 2 (storytelling): feeds that structured plan into a second OpenAI prompt that writes the markdown recap (opening paragraph, spotlight bullets, theme sections, optional “Other updates”).
- If either OpenAI call fails (e.g., missing `OPENAI_API_KEY`), the script falls back to a deterministic summary so the file is still created.

### Usage
```sh
export OPENAI_API_KEY=sk-...        # required for LLM mode
export OPENAI_MODEL=gpt-4o-mini     # optional override
export WEEKLY_SUMMARY_LIMIT=60      # cap posts sent to the model
WEEKLY_DATE=2025-10-25 FORCE_WEEKLY=1 bin/generate-weekly-summary  # backfill week ending Oct 25, 2025
```

Generated posts land in `_posts/` with a slugified filename matching the title (e.g., `2025-11-08-king-county-solutions-weekly-roundup-november-2-november-8-2025.md`). Links in the article point to the original `source_url` values. After running the script, rebuild the site (`bundle exec jekyll build` or `script/cibuild`) to validate the new roundup.

### Backfilling multiple weeks
Use `bin/backfill-weekly-summaries` to run the generator across several past weeks (defaults to 52 weeks/one year, ending with the current week). You can adjust how many weeks and where to start:

```sh
export OPENAI_API_KEY=sk-...
WEEKS=20 START_DATE=2025-01-04 bin/backfill-weekly-summaries
```

The wrapper sets `FORCE_WEEKLY=1` by default so existing files are overwritten; remove or override that env var if you’d prefer the original “skip if exists” behavior.
