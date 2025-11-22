# bin scripts

Utility commands that automate content imports, auditing, and metadata maintenance live in `bin/`. Run them from the repository root so relative paths resolve correctly.

## Quick reference

| Script | What it does |
| --- | --- |
| `audit-organization-topics` | Uses OpenAI to reconcile each organization’s topics against recent news coverage and optionally rewrites front matter. |
| `generate-organization-from-url` | Scrapes a site, asks OpenAI for metadata, and creates a new `_organizations/*.md` entry. |
| `generate-weekly-summary` | Builds a weekly roundup article from `_posts/`, grouping stories into themes with LLM assistance. |
| `import-rss-news` | Pulls fresh posts from partner RSS feeds defined in `_organizations/` and writes Markdown copies into `_posts/`. |
| `list-openai-models` | Lists available OpenAI model IDs for the current API key. |
| `summarize-news` | Fetches source articles for `_posts/` entries missing summaries, stores the original body, and writes an AI summary. |
| `summarize-topics` | Generates short descriptions for topic pages that lack an editorial summary. |
| `update-news-rss` | Crawls organization websites to locate RSS/Atom feeds and saves them back to `news_rss_url`. |

> Many scripts call the OpenAI API; export `OPENAI_API_KEY` before using them.

### `audit-organization-topics`

**Purpose**  
Reviews each `_organizations/*.md` file’s topics using `_topics/` metadata plus up to `--max-posts` recent news posts, letting OpenAI classify topics as `true`, `false`, or `unclear`. Can output a JSON report and optionally rewrite `topics` front matter entries.

**Usage**

- `bin/audit-organization-topics [--model MODEL] [--max-posts N] [--force] [--output report.json] [--apply]`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_TOPIC_AUDIT_MODEL` – overrides the default `gpt-4o-mini`.
- Caches per-organization responses under `.jekyll-cache/topic_audit/`; `--force` bypasses cache.

**Behavior notes**

- Without `--apply`, the script only prints or writes the audit report.
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

**Behavior notes**

- Skips creation if an existing `_organizations/*.md` already lists the same normalized `website`.
- Crawls up to the configured page limit on the target host, strips nav/scripts, and feeds truncated text to the LLM along with allowed topics/types inferred from existing files.
- Filters `jurisdictions` to known place titles (defaults to `King County` when the model returns unusable values), coerces `type` to the known set or falls back to `Community-Based Organization`, and keeps acronyms only if they are short uppercase strings.
- Attempts to auto-detect RSS/Atom and iCal links while scraping and fills `news_rss_url` / `events_ical_url` when absent.
- Generates a slug from the title, ensures uniqueness, writes ordered front matter plus a 100-word-capped summary body, and prints the created path.

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

**Behavior notes**

- Builds a “theme plan” JSON via one LLM call, then passes that plan plus post metadata into a second prompt that produces the final article (with themed sections and optional “Other updates”).
- Falls back to a deterministic, non-LLM summary if either call fails.
- Sets front matter with `source: King County Solutions`, `summarized: true`, and `openai_model` (or `fallback` if heuristics kick in), and adds a closing encouragement paragraph.

### `import-rss-news`

**Purpose**  
Imports recent partner updates from every `_organizations/*.md` that exposes `news_rss_url`, converts each RSS item into Markdown (with the original HTML saved in front matter), and writes it under `_posts/`.

**Usage**

- `bin/import-rss-news`

**Key env/config**

- Honors `news_rss_url` and optional metadata (e.g., titles) already in each organization file.
- Skips RSS items published more than `MAX_ITEM_AGE_DAYS` (365) days ago.

**Behavior notes**

- De-duplicates by checking existing `_posts/` entries whose `original_content` is present and `source_url` matches.
- Attempts to scrape the article body directly (preferring known selectors) if the RSS item lacks `content:encoded`.
- Converts HTML to Markdown via `ReverseMarkdown`, stores the upstream HTML in `original_content`, and saves the cleaned Markdown body beneath a single YAML front matter block.
- Stores SHA256 checksums for each feed in `bin/feed_checksums.yml` and skips reprocessing feeds whose checksum has not changed since the previous run.

### `list-openai-models`

**Purpose**  
Simple helper that echoes every model ID visible to the configured OpenAI account—useful for confirming newer `gpt-4o` variants.

**Usage**

- `bin/list-openai-models`

**Key env/config**

- `OPENAI_API_KEY` – required.

**Behavior notes**

- Returns one line per model and exits; no other arguments are supported.

### `summarize-news`

**Purpose**  
Backfills AI-written summaries for `_posts/` entries whose front matter lacks `summarized: true`. Preserves the original Markdown body, fetches the source article when possible, and writes a concise Markdown paragraph capped at ~100 words.

**Usage**

- `bin/summarize-news`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_SUMMARY_MODEL` – overrides the default `gpt-4o-mini`.

**Behavior notes**

- Tries to fetch the original article (scrubbing scripts/nav chrome) before sending truncated text (20k chars max) to the LLM; falls back to the stored Markdown body if the fetch fails.
- Retries failed API calls up to three times (sleeping between rate limits).
- Writes `original_markdown_body` once (if missing) and sets `summarized: true` in front matter.

### `summarize-topics`

**Purpose**  
Generates a short, resident-friendly description for each `_topics/*.md` file that lacks the `topic_summary_generated` flag, using the existing body (if any) as context for OpenAI.

**Usage**

- `bin/summarize-topics`

**Key env/config**

- `OPENAI_API_KEY` – required.
- `OPENAI_SUMMARY_MODEL` – overrides the default `gpt-4o-mini`.

**Behavior notes**

- Prompts the LLM for a single paragraph of ≤50 words and enforces the word budget by retrying up to three times.
- Stores the previous body under `original_topic_body` before overwriting it with the generated summary and marks `topic_summary_generated: true`.

### `update-news-rss`

**Purpose**  
Locates RSS/Atom feeds for organizations that have a `website` but no `news_rss_url`, using heuristics over the HTML, `<link rel="alternate">` tags, common “/feed” conventions, and secondary “news/blog” pages. Writes the discovered feed URL back to the organization’s front matter.

**Usage**

- `bin/update-news-rss`

**Key env/config**

- `OPENAI_API_KEY` is **not** required.
- `TARGETS=org-a.md,org-b.md` – restricts processing to a comma-delimited subset (filenames or `_organizations/<file>` paths).
- `LIMIT=10` – stop after inspecting N organizations.
- `DRY_RUN=1` – report findings without writing to disk.

**Behavior notes**

- Applies custom request headers, trims downloads (`HTML_MAX_BYTES`, `FEED_MAX_BYTES`), sleeps briefly between fetches, and ignores obvious comment feeds.
- If no feed is embedded on the homepage it probes the highest-scoring “secondary pages” (links mentioning news/blog/press/etc.) before giving up.
- Prints a summary of processed vs. updated files and lists each detected feed.
