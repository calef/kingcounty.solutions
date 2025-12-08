# Repository Guidelines

## Project Structure & Module Organization
- Jekyll sources live at the repo root; `_layouts`, `_includes`, and `_sass` control shared markup. Collections are in `_organizations`, `_places`, and `_topics`, while `_posts` holds imported news.
- Assets are under `assets/` (CSS/JS, favicons), and generated output lands in `_site/` (ignored by Git).
- Utility scripts in `bin/` and `script/` automate importing RSS feeds, updating schemas, and ensuring toolchains; read each script’s header before running.

## Build, Test, and Development Commands
- `script/bootstrap` — preferred entry point; installs Ruby/Bundler via mise helpers and runs `bundle install`.
- `script/server` — wraps `bundle exec jekyll serve --livereload` so you can preview at `http://127.0.0.1:4000`.
- `script/cibuild` — invokes `bundle exec jekyll build` plus any future CI checks; run locally before PRs.

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

### Tool Usage Efficiency
- Use parallel tool calls for independent operations and chain dependent shell commands with `&&` to minimize turns and side effects.
- Prefer `glob` and `grep` for searching, `view` for reading files, and `edit` for minimal, surgical edits; follow repository guidelines for file naming and indentation.
- Batch multiple edits to the same file in a single response for efficiency.

### Code Modification Principles
- Do not modify files under `_site/` or commit secrets; make the smallest possible change to fix an issue and document verification steps in the PR.
- Focus on surgical, minimal changes rather than broad refactoring unless explicitly requested.
- When fixing bugs, preserve existing behavior except for the specific issue being addressed.
- Always review the context of the code you're modifying to understand the full impact.

### Build and Testing
- `script/bootstrap`, `script/server`, and `script/cibuild` verify local builds, however agents lack permissions to run them.
- Run `bundle exec jekyll build` to validate structural changes and catch Liquid errors.
- Run `bundle exec rake test` to execute the test suite after code changes.
- For script changes, test with `--help` or dry-run flags when available.

### Security Awareness
- Never commit secrets, API keys, or credentials.
- Validate and sanitize any user input in scripts.
- Use environment variables for sensitive configuration.
- Review new dependencies for security advisories.

### Communication and Collaboration
- Keep messages concise and actionable so other agents can pick up work quickly.
- Document verification steps in PR descriptions (commands run, expected behavior).
- script/ and bin/ scripts should have execute permissions.
- Link related issues and note any follow-up work required.
