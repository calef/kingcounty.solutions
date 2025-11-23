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
- `bin/import-rss-news` — pulls latest partner news into `_posts/`. Delete a post’s `original_content` to force re-import.
- `bin/summarize-news` — generates AI summaries for posts lacking `summarized: true`, preserving the original markdown body in `original_markdown_body`.

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
