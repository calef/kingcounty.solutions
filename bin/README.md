# bin scripts

Utility commands that automate content imports, auditing, and metadata maintenance live in `bin/`. Run them from the repository root so relative paths resolve correctly.

## Quick reference

| Script | What it does |
| --- | --- |
| `audit-organization-topics` | Uses OpenAI to reconcile each organization’s topics against recent news coverage and optionally rewrites front matter. |
| `generate-organization-from-url` | Scrapes a site, asks OpenAI for metadata, and creates a new `_organizations/*.md` entry. |
| `generate-weekly-summary` | Builds a weekly roundup article from `_posts/`, grouping stories into themes with LLM assistance. |
| `extract-images-from-content` | Pulls image URLs from `original_markdown_body` (if present), downloads them into `assets/images`, hashes/renames files, and links image IDs into `_posts/`, `_events/`, and `_images/`. |
| `import-content-from-feeds` | Runs the RSS and iCal importers back-to-back so partner news and events flow into `_posts/` and `_events/`, normalizing URLs and metadata where possible. |
| `list-openai-models` | Lists available OpenAI model IDs for the current API key. |
| `summarize-content` | Generates AI-written summaries for `_posts/` and `_events/` entries that lack `summarized: true`, preserving the original Markdown body before replacing it with the short summary. |
| `update-organization-feed-urls` | Crawls organization websites to locate RSS/Atom and iCal feeds, updating `news_rss_url` and `events_ical_url`. |
| `tidy-frontmatter` | Normalizes Markdown front matter (sorted keys, consistent delimiters, and tidy spacing between the delimiter and body). |

> Many scripts call the OpenAI API; export `OPENAI_API_KEY` before using them.

### `audit-organization-topics`

**Purpose**  
Reviews each `_organizations/*.md` file’s topics using `_topics/` metadata plus up to `--max-posts` recent news posts, letting OpenAI classify topics as `true`, `false`, or `unclear`. Can output a JSON report and optionally rewrite `topics` front matter entries.

**Usage**

- `bin/audit-organization-topics [--model MODEL] [--max-posts N] [--force] [--output report.json] [--apply]`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_TOPIC_AUDIT_MODEL` – overrides the default `gpt-4o-mini`.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Raise to `INFO` to see per-organization progress and summaries.
- Caches per-organization responses under `.jekyll-cache/topic_audit/`; `--force` bypasses cache.

**Behavior notes**

- Without `--apply`, the script only logs or writes the audit report results.
- When `--apply` is supplied, it edits each organization file by removing unsupported topics and appending new ones suggested by the audit, keeping the list sorted and unique.
- Includes up to `--max-posts` (default 5) of the organization’s recent `_posts/` content in the LLM prompt.

### `generate-organization-from-url`

**Purpose**  
Scrapes a single organization website (following same-host links) and asks OpenAI to draft front matter and a short summary, then writes a new `_organizations/<slug>.md` entry.

**Usage**

- `bin/generate-organization-from-url https://example.org`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_ORG_MODEL` – overrides the default `gpt-4o-mini`.
- `ORG_SCRAPER_MAX_PAGES` – how many same-host pages to crawl (default 5).
- `ORG_SCRAPER_PAGE_SNIPPET` – max characters of text per page sent to the prompt (default 3000).
- `ORG_SCRAPER_TIMEOUT` – HTTP open/read timeout in seconds (default 10).
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Set to `INFO` to see skip reasons and newly created paths.

**Behavior notes**

- Skips creation if an existing `_organizations/*.md` already lists the same normalized `website`.
- Crawls up to the configured page limit on the target host, strips nav/scripts, and feeds truncated text to the LLM along with allowed topics/types inferred from existing files.
- Filters `jurisdictions` to known place titles (defaults to `King County` when the model returns unusable values), coerces `type` to the known set or falls back to `Community-Based Organization`, and keeps acronyms only if they are short uppercase strings.
- Attempts to auto-detect RSS/Atom and iCal links while scraping and fills `news_rss_url` / `events_ical_url` when absent.
- Generates a slug from the title, ensures uniqueness, writes ordered front matter plus a 100-word-capped summary body, and logs the created path when the log level allows it.

### `generate-weekly-summary`

**Purpose**  
Builds an editorial roundup post for the current week (Saturday–Friday window) by clustering `_posts/` entries into themes, drafting a Markdown article with OpenAI, and saving it back into `_posts/` under the ending Saturday’s date.

**Usage**

- `bin/generate-weekly-summary`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_MODEL` – overrides the default `gpt-4o-mini`.
- `WEEKLY_SUMMARY_LIMIT` – caps how many posts are passed to the LLM for theme planning (default 60).
- `WEEKLY_DATE` – optional `YYYY-MM-DD` anchor date to regenerate a specific week.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Raise to `INFO` for creation notices and fallback explanations.

**Behavior notes**

- Builds a “theme plan” JSON via one LLM call, then passes that plan plus post metadata into a second prompt that produces the final article (with themed sections and optional “Other updates”).
- Falls back to a deterministic, non-LLM summary if either call fails.
- Sets front matter with `source: King County Solutions`, `summarized: true`, and `openai_model` (or `fallback` if heuristics kick in), and adds a closing encouragement paragraph.

### `extract-images-from-content`

**Purpose**  
Downloads images referenced in each post or event `original_markdown_body`, renames them to their SHA256 checksum plus extension, writes `_images/<checksum>.md` entries, and stores the related image checksums back into the source front matter.

**Usage**

- `bin/extract-images-from-content`

**Key env/config**

- `IMAGE_OPEN_TIMEOUT` – HTTP open timeout in seconds (default 10).
- `IMAGE_READ_TIMEOUT` – HTTP read timeout in seconds (default 30).
- `IMAGE_MIN_DIMENSION` – minimum width/height in pixels for WebP conversions (default 300). Assets smaller than this threshold are skipped.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to see per-post updates and run summaries.

**Behavior notes**

- Skips entries without `original_markdown_body` or without image references; supports Markdown `![]()` and `<img>` tags with `http/https` sources.
- Skips entries that already have an `images` front matter attribute; intended for one-time population.
- Avoids redownloading the same URL within a run; writes files under `assets/images/<checksum>.webp` (or the original extension when conversion fails).
- Converts raster image downloads (JPEG/PNG/GIF/BMP/TIFF) into WebP via ImageMagick (`mini_magick` must be bundled and ImageMagick’s `magick`/`convert` binary available); non-raster/media or failed conversions leave the original bytes/extension untouched.
- Skips storing WebP assets whose dimensions fall below `IMAGE_MIN_DIMENSION`, logging a per-post warning and incrementing the run summary’s `skipped_small_images` counter.
- Creates `_images/<checksum>.md` with `checksum`, optional `title` (set only when the image had alt text), `image_url`, `source_url`, and copies `source`/`date` from the originating entry; appends discovered checksums to an entry’s `images` array without removing existing entries.
- Logs WARN-level issues for missing front matter or failed downloads/conversions, INFO for updates/empty images actions, DEBUG for already-processed posts, and prints a per-run summary when the log level allows it.

### `import-content-from-feeds`

**Purpose**  
Runs the RSS news importer followed by the iCal events importer so `_posts/` and `_events/` reflect the latest partner updates declared in `_organizations/*.md`.

**Usage**

- `bin/import-content-from-feeds`

**Key env/config**

- Honors each organization’s `news_rss_url`, `events_ical_url`, and metadata when creating posts/events.
- Skips RSS items older than `rss_max_item_age_days` (configured in `_config.yml`, default 365) days ago.
- `RSS_WORKERS` – thread count for fetching/parsing RSS feeds in parallel (default 6).
- `RSS_OPEN_TIMEOUT` / `RSS_READ_TIMEOUT` – per-request timeouts in seconds (defaults 5/10) for feed fetches and article-body scraping.
- `ICAL_WORKERS` – thread count for the events importer (default 6); lower it if feed endpoints are sensitive.
- `LOG_LEVEL` – logging level shared by both importers (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to surface per-feed/per-organization summaries.

**Behavior notes**

- News import: normalizes and validates each RSS item URL before writing `_posts/`, skips duplicates already present in front matter, scrapes article bodies when the feed lacks `content:encoded`, converts HTML to Markdown via `ReverseMarkdown`, and saves the upstream HTML in `original_content`.
- Events import: scans every `_organizations/*.md` with `events_ical_url`, downloads each calendar, skips events that are missing metadata, in the past, or too far in the future, normalizes canonical URLs to avoid duplicates, fetches event body content when possible, and writes `_events/<date>-<slug>.md` with `original_content`/`original_markdown_body` copies.
- Both importers parallelize work with small worker pools, log per-source summaries, and keep running when individual feeds fail so a single bad endpoint never blocks the rest.

### `enforce-content-age`

**Purpose**  
Deletes `_posts/*.md` (and their referenced `_images/*.md` metadata plus any `assets/images/<hash>.*` files) whose `date` front matter falls outside of the configured window, then removes `_events/*.md` entries whose `start_date` is earlier than the current time.

**Usage**

 - `bin/enforce-content-age`

**Key env/config**

 - `content_max_age_days` – configured in `_config.yml`, defaults to 365. The script honors this value and silently skips content that is already within the threshold.

**Behavior notes**

 - Loads `_config.yml` for `content_max_age_days`; missing or invalid values fall back to 365 days.
 - Removes posts older than the threshold, then deletes referenced `_images/` metadata files and any assets named after those image checksums (e.g., `assets/images/<hash>.webp`) unless another post still references the same checksum.
 - After post cleanup, scans `_events/` and removes events whose `start_date` timestamps are already in the past (relative to the time the script runs).
 - Prints a short summary of how many posts and images were removed so you can verify the cleanup before committing.

### `list-openai-models`

**Purpose**  
Simple helper that echoes every model ID visible to the configured OpenAI account—useful for confirming newer `gpt-4o` variants.

**Usage**

- `bin/list-openai-models`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Set to `INFO` to see the model list.

**Behavior notes**

- Returns one line per model and exits; no other arguments are supported.

### `summarize-content`

**Purpose**  
Runs both news and event summarizers so `_posts/` and `_events/` files missing `summarized: true` gain a concise Markdown summary while keeping the original Markdown body in front matter. Both content types also receive automatic topic classification when the `topics` array is empty.

**Usage**

- `bin/summarize-content`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_MODEL` – overrides the default `gpt-4o-mini` for news summaries (and topic classification defaults).
- `OPENAI_EVENT_MODEL` – optional override for event summaries; falls back to `OPENAI_MODEL`.
- `OPENAI_TOPIC_MODEL` – optional override for the topic classifier (defaults to `OPENAI_MODEL` when unset).
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Use `INFO` to see update summaries without surfacing all warnings.

**Behavior notes**

- Processes news posts first, preserving any existing body as `original_markdown_body`, fetching the source article (20k character cap) when available, generating a summary, and classifying topics if needed (marking `published: false` when no topics match).
- Runs through `_events/` afterward, pulling article text either from the remote source or stored body, generating an event-focused summary, classifying topics when missing, and flagging the event as unpublished if no topics apply.
- Retries OpenAI calls up to three times on rate limits, logging WARN messages for API or fetch issues and summarizing the run totals at INFO level.
- Leaves files untouched when `summarized: true` is already present, but you can force a re-run by deleting that flag (or the stored summary) before invoking the script.

### `update-organization-feed-urls`

**Purpose**  
Locates RSS/Atom and iCal feeds for organizations that have a `website` but are missing either `news_rss_url` or `events_ical_url`, using heuristics over the HTML, `<link rel="alternate">` tags, common “/feed” conventions, and secondary “news/blog”/calendar pages. Writes any newly discovered URLs back to the organization’s front matter; skips files that already expose both fields.

**Usage**

- `bin/update-organization-feed-urls`

**Key env/config**

- `OPENAI_API_KEY` is **not** required.
- `TARGETS=org-a.md,org-b.md` – restricts processing to a comma-delimited subset (filenames or `_organizations/<file>` paths).
- `LIMIT=10` – stop after inspecting N organizations.
- `DRY_RUN=1` – report findings without writing to disk.
- `LOG_LEVEL` – logging level shared by all scripts (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL`; default `WARN`). Raise to `INFO` to see per-organization progress and summaries.

**Behavior notes**

- Applies custom request headers, trims downloads (`HTML_MAX_BYTES`, `FEED_MAX_BYTES`), sleeps briefly between fetches, and ignores obvious comment feeds.
- If no feed is embedded on the homepage it probes the highest-scoring “secondary pages” (links mentioning news/blog/press/etc.) before giving up.
- Updates either `news_rss_url` or `events_ical_url` (or both) with the newly discovered URLs and skips organizations that already expose both fields; logs INFO-level progress as organizations are processed along with a final summary listing each feed type it wrote.

### `tidy-frontmatter`

**Purpose**  
Enforces a tidy YAML front-matter block for Markdown files so other scripts can process a consistent format.

**Usage**

- `bin/tidy-frontmatter PATH...`

**Behavior notes**

- `PATH` accepts a single Markdown file or directory; directories are processed recursively.
- The tidier sorts YAML keys alphabetically, trims duplicate delimiters, and leaves a single blank line between the closing `---` and the Markdown body.
- Runs via `Mayhem::FrontMatterTidier`, so other scripts can call `tidy_markdown` before writing Markdown files.
