# script helpers

The `script/` directory contains lightweight automation used during setup, local development, and CI. Run them from the repository root so relative paths and config files are resolved correctly.

## Quick reference

| Script | Purpose |
| --- | --- |
| `bootstrap` | Installs the Bundler version listed in `.bundler-version` (via `ensure-bundler`) and runs `bundle install`. |
| `cibuild` | Cleans the workspace, ensures dependencies, and runs `bundle exec jekyll build` with `JEKYLL_ENV=production` and drafts enabled. |
| `ensure-bundler` | Installs the pinned Bundler version after verifying Ruby is installed. |
| `ensure-cmake` | Installs `cmake` via Homebrew or `apt` (Ubuntu only). |
| `ensure-curl` | Installs `curl` plus SSL development headers when needed. |
| `ensure-git` | Installs Git for macOS (Homebrew) or Ubuntu. |
| `ensure-homebrew` | Boots Homebrew on macOS or exits with instructions if missing. |
| `ensure-libffi` | Installs libffi headers/libraries needed for Ruby builds. |
| `ensure-libyaml` | Installs libyaml headers/libraries needed for Ruby builds. |
| `ensure-mise` | Installs the `mise` toolchain manager and wires it into your shell rc file. |
| `ensure-ruby` | Validates `.ruby-version`/`.ruby-gemset`, installs prerequisites, and uses `mise` to install the required Ruby. |
| `server` | Pulls the latest dependencies (`script/update`) and runs `bundle exec jekyll serve --livereload --host 0.0.0.0`. |
| `setup` | Removes `_site`, `.jekyll-cache`, and `.jekyll-metadata` to give CI/build scripts a clean slate. |
| `update` | Runs `script/bootstrap`; use after pulling remote changes to make sure gems are current. |

> Most installers have macOS and Ubuntu paths only. Other platforms should rely on containerized builds or install prerequisites manually.

### `bootstrap`

- Wraps `script/ensure-bundler` so the pinned Bundler version is installed along with the required Ruby.  
- Calls `bundle install` (which respects `Gemfile.lock`), ensuring local dependencies match CI.  
- Use as the primary setup entry point (`script/bootstrap`) before running other scripts.

### `cibuild`

- Runs `script/setup` (cleans build artifacts), then executes `bundle exec jekyll build --drafts` with `JEKYLL_ENV=production`.  
- Intended to mirror CI behavior locally; use before opening a PR to catch Liquid/front-matter errors.  
- Respects any environment variables recognized by `jekyll build` (e.g., `JEKYLL_ENV` override).

### `ensure-*` installers

All `ensure-*` scripts follow the same pattern: detect the OS, ensure Homebrew (macOS) or apt packages (Ubuntu) are available, and install the named dependency if missing. Each exits with an error on unsupported platforms so pipelines fail loudly.

- `ensure-bundler` – checks `.bundler-version`, calls `ensure-ruby`, then `gem install bundler -v <version>`.  
- `ensure-cmake`, `ensure-curl`, `ensure-git`, `ensure-libffi`, `ensure-libyaml` – install the respective tools/packages.  
- `ensure-homebrew` – validates the host is macOS and installs Homebrew if absent.  
- `ensure-mise` – installs the `mise` version manager and appends its activation line to your shell rc file (prints instructions for non-interactive shells).  
- `ensure-ruby` – requires `.ruby-version` and `.ruby-gemset`, installs build deps on Ubuntu, ensures toolchain helpers (`ensure-*`) are run, then uses `mise use ruby@<version>` to install/switch Ruby.

### `server`

- Executes `script/update` (which runs `script/bootstrap`) before launching `bundle exec jekyll serve --livereload --host 0.0.0.0`.  
- Use for local preview; the livereload flag watches files, and binding to `0.0.0.0` allows LAN/device testing.

### `setup`

- Deletes `_site`, `.jekyll-cache`, and `.jekyll-metadata` so subsequent builds start clean.  
- Safe to run whenever Jekyll cache corruption is suspected.

### `update`

- Convenience wrapper that calls `script/bootstrap`; run after fetching remote changes to pull new gems or Bundler updates automatically.
