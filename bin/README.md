# bin scripts

Utility commands that automate content imports, auditing, and metadata maintenance live in `bin/`. Run them from the repository root so relative paths resolve correctly.

## Quick reference

| Script | What it does |
| --- | --- |
| `mayhem` | Unified entry point for content management commands (see `mayhem help` for details). |
| `generate-weekly-summary` | Builds a weekly roundup article from `_posts/`, grouping stories into themes with LLM assistance. |

> Many scripts call the OpenAI API; export `OPENAI_API_KEY` before using them.

## Mayhem commands

The `mayhem` script consolidates content management functionality. Run `mayhem help` to see all available commands:

- `mayhem audit-topics` – Uses OpenAI to reconcile each organization's topics against recent news coverage and optionally rewrites front matter.
- `mayhem expire` – Deletes posts and events outside configured age window.
- `mayhem extract-events` – Analyzes news posts to identify and create event entries.
- `mayhem extract-images` – Downloads images from posts/events and creates image metadata.
- `mayhem ingest` – Runs import-content, summarize, extract-events, summarize again, extract-images, then expire.
- `mayhem new-organization` – Scrapes a site and creates a new `_organizations/*.md` entry.
- `mayhem import-content` – Runs RSS and iCal importers to fetch partner content.
- `mayhem ls-models` – Lists available OpenAI model IDs.
- `mayhem summarize` – Generates AI summaries for posts and events.
- `mayhem tidy` – Normalizes Markdown front matter formatting.

## Freezing files during automation

Set `locked: true` in a post or event's front matter to freeze it in place. Importers, summarizers, and the image extractor all detect this flag and skip the entry so curated edits stay untouched while the rest of the pipeline continues to run.

### `mayhem audit-topics`

#### Purpose

Reviews each `_organizations/*.md` file's topics using `_topics/` metadata plus up to `--max-posts` recent news posts, letting OpenAI classify topics as `true`, `false`, or `unclear`. Can output a JSON report and optionally rewrite `topics` front matter entries.

#### Usage

- `mayhem audit-topics [--model MODEL] [--max-posts N] [--force] [--output report.json] [--apply]`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `OPENAI_TOPIC_AUDIT_MODEL` – overrides the default `gpt-4o-mini`.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Raise to `INFO` to see per-organization progress and summaries.
- Caches per-organization responses under `.jekyll-cache/topic_audit/`; `--force` bypasses cache.

#### Behavior notes

- Without `--apply`, the script only logs or writes the audit report results.
- When `--apply` is supplied, it edits each organization file by removing unsupported topics and appending new ones suggested by the audit, keeping the list sorted and unique.
- Includes up to `--max-posts` (default 5) of the organization's recent `_posts/` content in the LLM prompt.

### `mayhem new-organization`

#### Purpose

Scrapes a single organization website (following same-host links) and asks OpenAI to draft front matter and a short summary, then writes a new `_organizations/<slug>.md` entry.

#### Usage

- `mayhem new-organization URL`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `OPENAI_ORG_MODEL` – overrides the default `gpt-4o-mini`.
- `ORG_SCRAPER_MAX_PAGES` – how many same-host pages to crawl (default 5).
- `ORG_SCRAPER_PAGE_SNIPPET` – max characters of text per page sent to the prompt (default 3000).
- `ORG_SCRAPER_TIMEOUT` – HTTP open/read timeout in seconds (default 10).
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Set to `INFO` to see skip reasons and newly created paths.

#### Behavior notes

- Skips creation if an existing `_organizations/*.md` already lists the same normalized `website`.
- Crawls up to the configured page limit on the target host, strips nav/scripts, and feeds truncated text to the LLM along with allowed topics/types inferred from existing files.
- Coerces `type` to the known set or falls back to `Community-Based Organization`, and keeps acronyms only if they are short uppercase strings.
- Attempts to auto-detect RSS/Atom and iCal links while scraping and fills `news_rss_url` / `events_ical_url` when absent.
- Generates a slug from the title, ensures uniqueness, writes ordered front matter plus a 100-word-capped summary body, and logs the created path when the log level allows it.

### `generate-weekly-summary`

#### Purpose

Builds an editorial roundup post for the current week (Saturday–Friday window) by clustering `_posts/` entries into themes, drafting a Markdown article with OpenAI, and saving it back into `_posts/` under the ending Saturday's date.

#### Usage

- `bin/generate-weekly-summary`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `OPENAI_MODEL` – overrides the default `gpt-4o-mini`.
- `WEEKLY_SUMMARY_LIMIT` – caps how many posts are passed to the LLM for theme planning (default 60).
- `WEEKLY_DATE` – optional `YYYY-MM-DD` anchor date to regenerate a specific week.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Raise to `INFO` for creation notices and fallback explanations.

#### Behavior notes

- Builds a "theme plan" JSON via one LLM call, then passes that plan plus post metadata into a second prompt that produces the final article (with themed sections and optional "Other updates").
- Falls back to a deterministic, non-LLM summary if either call fails.
- Sets front matter with `source: King County Solutions`, `summarized: true`, and `openai_model` (or `fallback` if heuristics kick in), and adds a closing encouragement paragraph.

### `mayhem extract-images`

#### Purpose

Downloads images referenced in each post or event `original_markdown_body`, renames them to their SHA256 checksum plus extension, writes `_images/<checksum>.md` entries, and stores the related image checksums back into the source front matter.

#### Usage

- `mayhem extract-images`

#### Key env/config

- `IMAGE_OPEN_TIMEOUT` – HTTP open timeout in seconds (default 10).
- `IMAGE_READ_TIMEOUT` – HTTP read timeout in seconds (default 30).
- `IMAGE_MIN_DIMENSION` – minimum width/height in pixels for WebP conversions (default 300). Assets smaller than this threshold are skipped.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to see per-post updates and run summaries.

#### Behavior notes

- Skips entries without `original_markdown_body` or without image references; supports Markdown `![]()` and `<img>` tags with `http/https` sources.
- Skips entries that already have an `images` front matter attribute; intended for one-time population.
- Respects `locked: true` by leaving the entry untouched, preserving curated content.
- Avoids redownloading the same URL within a run; writes files under `assets/images/<checksum>.webp` (or the original extension when conversion fails).
- Converts raster image downloads (JPEG/PNG/GIF/BMP/TIFF) into WebP via ImageMagick (`mini_magick` must be bundled and ImageMagick's `magick`/`convert` binary available); non-raster/media or failed conversions leave the original bytes/extension untouched.
- Skips storing WebP assets whose dimensions fall below `IMAGE_MIN_DIMENSION`, logging a per-post warning and incrementing the run summary's `skipped_small_images` counter.
- Creates `_images/<checksum>.md` with `checksum`, optional `title` (set only when the image had alt text), `image_url`, `source_url`, and copies `source`/`date` from the originating entry; appends discovered checksums to an entry's `images` array without removing existing entries.
- Logs WARN-level issues for missing front matter or failed downloads/conversions, INFO for updates/empty images actions, DEBUG for already-processed posts, and prints a per-run summary when the log level allows it.

### `mayhem import-content`

#### Purpose

Runs the RSS news importer and the iCal events importer so `_posts/` and `_events/` reflect the latest partner updates declared in `_organizations/*.md`. This is the primary script for ingesting content.

#### Usage

- `mayhem import-content`

#### Key env/config

- Honors each organization's `news_rss_url`, `events_ical_url`, and metadata when creating posts/events.
- Skips RSS items older than `rss_max_item_age_days` (configured in `_config.yml`, default 365) days ago.
- `RSS_WORKERS` – thread count for fetching/parsing RSS feeds in parallel (default 6).
- `RSS_OPEN_TIMEOUT` / `RSS_READ_TIMEOUT` – per-request timeouts in seconds (defaults 5/10) for feed fetches and article-body scraping.
- `ICAL_WORKERS` – thread count for the events importer (default 6); lower it if feed endpoints are sensitive.
- `LOG_LEVEL` – logging level shared by both importers (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to surface per-feed/per-organization summaries.

#### Behavior notes

- News import: normalizes and validates each RSS item URL before writing `_posts/`, skips duplicates already present in front matter, scrapes article bodies when the feed lacks `content:encoded`, and saves the upstream HTML in `feed_content` with a `feed_content_checksum`.
- Events import: scans every `_organizations/*.md` with `events_ical_url`, downloads each calendar, skips events that are missing metadata, in the past, or too far in the future, normalizes canonical URLs to avoid duplicates, fetches event body content when possible, and writes `_events/<date>-<slug>.md` with `feed_content`/`feed_content_checksum` copies.
- Event extraction from posts: handled by `mayhem extract-events`.
- All operations honor `locked: true` on disk, skipping rewrites while still registering source URLs to avoid future duplicates.
- All operations parallelize work with small worker pools, log per-source summaries, and keep running when individual feeds fail so a single bad endpoint never blocks the rest.

### `mayhem ingest`

#### Purpose

Runs the full content pipeline in order so one command can be used for routine updates.

#### Usage

- `mayhem ingest`

#### Behavior notes

- Executes `import-content`, `summarize`, `extract-events`, another `summarize`, `extract-images`, then `expire` in sequence.
- Respects `locked: true` within each step; check individual commands for their specific options and environment variables.

### `mayhem extract-events`

#### Purpose

Analyzes news posts to identify event announcements using LLM, creates corresponding event entries in `_events/`, and cross-links posts to their generated events. Designed for organizations that publish event announcements in their news feeds but don't provide iCal feeds.

#### Usage

- `mayhem extract-events`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `OPENAI_EVENT_EXTRACTION_MODEL` – overrides the default `gpt-4o-mini`.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to see per-post extraction progress.

#### Behavior notes

- Only processes posts in `_posts/` whose front matter has `summarized: true`; unsummarized entries are skipped so you can summarize first.
- Processes **all** posts in `_posts/` directory, skipping only those marked with `locked: true`, `published: false`, or `events_extracted: true`.
- Sends post title and content to the LLM to extract structured event data (title, date/time, location, description).
- The LLM is instructed to extract only future events relative to the article's publication date, filtering out past events automatically.
- Creates `_events/<date>-<slug>.md` entries with `generated_from_post: true` flag and links them in the post's `events` front matter array.
- Uses post's `source_url` as the event's `source_url` for proper attribution.
- Marks posts with `events_extracted: true` to avoid reprocessing, even when no events are found.
- Generated events are automatically cleaned up when their source posts are removed by `mayhem expire` or when they expire via `StaleEventCleaner`.

### `mayhem expire`

#### Purpose

Deletes `_posts/*.md` (and their referenced `_images/*.md` metadata plus any `assets/images/<hash>.*` files) whose `date` front matter falls outside of the configured window, then removes `_events/*.md` entries whose `start_date` is earlier than the current time.

#### Usage

- `mayhem expire`

#### Key env/config

- `content_max_age_days` – configured in `_config.yml`, defaults to 365. The script honors this value and silently skips content that is already within the threshold.

#### Behavior notes

- Loads `_config.yml` for `content_max_age_days`; missing or invalid values fall back to 365 days.
- Removes posts older than the threshold, then deletes referenced `_images/` metadata files and any assets named after those image checksums (e.g., `assets/images/<hash>.webp`) unless another post still references the same checksum.
- Also removes events that were `generated_from_post: true` when their source posts are removed.
- After post cleanup, scans `_events/` and removes events whose `start_date` timestamps are already in the past (relative to the time the script runs), and cleans up any `events` references in posts that link to the removed events.
- Prints a short summary of how many posts, events, and images were removed so you can verify the cleanup before committing.

### `mayhem ls-models`

#### Purpose

Simple helper that echoes every model ID visible to the configured OpenAI account—useful for confirming newer `gpt-4o` variants.

#### Usage

- `mayhem ls-models`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Set to `INFO` to see the model list.

#### Behavior notes

- Returns one line per model and exits; no other arguments are supported.

### `mayhem summarize`

#### Purpose

Runs both news and event summarizers so `_posts/` and `_events/` files missing `summarized: true` gain a concise Markdown summary while keeping the original Markdown body in front matter. Both content types also receive automatic topic classification when the `topics` array is empty.

#### Usage

- `mayhem summarize`

#### Key env/config

- `OPENAI_API_KEY` – required.
- `OPENAI_MODEL` – overrides the default `gpt-4o-mini` for news summaries (and topic classification defaults).
- `OPENAI_EVENT_MODEL` – optional override for event summaries; falls back to `OPENAI_MODEL`.
- `OPENAI_TOPIC_MODEL` – optional override for the topic classifier (defaults to `OPENAI_MODEL` when unset).
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to see update summaries without surfacing all warnings.

#### Behavior notes

- Processes news posts first, preserving any existing body as `original_markdown_body`, fetching the source article (20k character cap) when available, generating a summary, and classifying topics if needed (marking `published: false` when no topics match).
- Runs through `_events/` afterward, pulling article text either from the remote source or stored body, generating an event-focused summary, classifying topics when missing, and flagging the event as unpublished if no topics apply.
- Retries OpenAI calls up to three times on rate limits, logging WARN messages for API or fetch issues and summarizing the run totals at INFO level.
- Leaves files untouched when `summarized: true` is already present, but you can force a re-run by deleting that flag (or the stored summary) before invoking the script.
- Honors `locked: true` across posts and events, skipping both summary and topic updates for frozen entries.

### `mayhem tidy`

#### Purpose

Enforces a tidy YAML front-matter block for Markdown files so other scripts can process a consistent format.

#### Usage

- `mayhem tidy PATH...`

#### Behavior notes

- `PATH` accepts a single Markdown file or directory; directories are processed recursively.
- The tidier sorts YAML keys alphabetically, trims duplicate delimiters, and leaves a single blank line between the closing `---` and the Markdown body.
- Runs via `Mayhem::FrontMatter::Tidier`, so other scripts can call `tidy_markdown` before writing Markdown files.
