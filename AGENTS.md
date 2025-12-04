# Repository Guidelines

## Project Structure & Module Organization
- Jekyll sources live at the repo root; `_layouts`, `_includes`, and `_sass` control shared markup. Collections are in `_organizations`, `_places`, and `_topics`, while `_posts` holds imported news.
- Assets are under `assets/` (CSS/JS, favicons), and generated output lands in `_site/` (ignored by Git).
- Utility scripts in `bin/` and `script/` automate importing RSS feeds, updating schemas, and ensuring toolchains; read each script’s header before running.

## Build, Test, and Development Commands
- `script/bootstrap` — preferred entry point; installs Ruby/Bundler via mise helpers and runs `bundle install`.
- Toolchains are managed with `mise`; if you open a new shell run `mise exec ruby@$(cat .ruby-version) -- <command>` (or source its activation line) so Ruby/Bundler versions match `.ruby-version`/`.bundler-version`.
- `script/server` — wraps `bundle exec jekyll serve --livereload` so you can preview at `http://127.0.0.1:4000`.
- `script/cibuild` — invokes `bundle exec jekyll build` plus any future CI checks; run locally before PRs.
- `bin/import-rss-news` — pulls latest partner news into `_posts/`. The importer now normalizes and validates item URLs (using an organization’s `website` as a base when needed) and will not persist invalid `source_url` values; deleting a post’s `source_url` can force re-import.
- `bin/summarize-news` — generates AI summaries for posts lacking `summarized: true`.

## Coding Style & Naming Conventions
- Use two spaces for indentation in Liquid templates, Markdown front matter, and Ruby scripts. Keep YAML keys lowercase with snake_case (e.g., `parent_place`).
- When adding pages, name files with kebab-case (e.g., `places.md`) and keep collection documents singular (`title: Auburn`, filename `auburn.md`).
- Prefer the existing inline-comment style: concise and only when necessary to explain non-obvious logic.

## Testing Guidelines
- This repo relies on Jekyll’s build as the validation step. Always run `bundle exec jekyll build` after structural changes and before opening a PR to catch Liquid or front-matter errors.
- For scripts, add minimal smoke tests (e.g., run with `--help` or dry-run flags) if modifying behavior. No dedicated test framework is configured.

## Commit & Pull Request Guidelines
- Follow imperative, concise commit messages (`Add places hierarchy layout`, `Fix RSS importer skip logic`).
- PRs should describe what changed, why, and how to verify (commands run, screenshots for UI tweaks). Link related issues and note any follow-up work or manual steps required.
- Keep diffs focused; split refactors from feature work when practical, and ensure `_site/` artifacts or local caches are never committed.

## Agent guidance
- Call the `report_intent` tool on your first tool-calling turn and whenever you move between major phases (e.g., exploring → editing → testing).
- When asked about this CLIs capabilities, call `fetch_copilot_cli_documentation` first and use its output to answer.
- Use parallel tool calls for independent operations and chain dependent shell commands with `&&` to minimize turns and side effects.
- Prefer `glob` and `grep` for searching, `view` for reading files, and `edit` for minimal, surgical edits; follow repository guidelines for file naming and indentation.
- Do not modify files under `_site/` or commit secrets; make the smallest possible change to fix an issue and document verification steps in the PR.
- Use `script/bootstrap`, `script/server`, and `script/cibuild` to set up and verify local builds.
- Keep messages concise and actionable so other agents can pick up work quickly.

