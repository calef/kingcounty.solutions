# kingcounty.solutions

Aggregates public service resources into a simple, searchable website to help people quickly find the support they need.

See `bin/README.md` and `script/README.md` for the automation helpers that handle data imports, audits, environment setup, and local preview workflows.

## Freezing imported entries

Automation can leave curated edits intact by setting `locked: true` in a post or event’s front matter. When this flag is present, the RSS/iCal importers, AI summarizers, and image extractor all skip the file entirely so the current body/front matter stay untouched while the rest of the pipeline continues to run.

## Sitemap

The `jekyll-sitemap` plugin is enabled so every build emits an up-to-date `sitemap.xml` at the site root for search engines and site audits.

## Tests

This repo uses Minitest for any Ruby automation or helpers. `bundle exec rake test` invokes `parallel_tests` so the suite runs across multiple workers. To run sequentially (for debugging), disable the parallel runner or pass `PARALLEL_TEST_PROCESSORS=1` before invoking the task:

```sh
bundle exec rake test
PARALLEL_TEST_PROCESSORS=1 bundle exec rake test
```

Run the integrity checks:

```sh
bin/mayhem check-integrity
RUN_EXPENSIVE_TESTS=true bin/mayhem check-integrity
```

`RUN_EXPENSIVE_TESTS` opts into the HTML5 validator; additional arguments (like `--name` or `--seed`) are passed straight through to Minitest.

## Podman dev container (macOS)

This setup keeps Codex and all tooling inside a Podman container while you edit locally in Nova. The container mounts only this repo at `/work` and does not mount your home directory, SSH keys, or any container engine sockets.

### Prerequisites

- Install Podman (no Docker Desktop).
- Initialize and start the Podman VM:

```sh
podman machine init
podman machine start
```

### Build the image

```sh
podman build -f Containerfile -t kingcounty-solutions-dev .
```

### Start the long-lived dev container

```sh
export DEV_CONTAINER_SSH_PASSWORD="set-a-local-password"
script/dev-container/start
```

The start script prints a generated password if `DEV_CONTAINER_SSH_PASSWORD` is not set. Re-running it with `DEV_CONTAINER_SSH_PASSWORD` set resets the SSH password. Override defaults with `DEV_CONTAINER_NAME`, `DEV_CONTAINER_IMAGE`, `DEV_CONTAINER_SSH_PORT`, or `DEV_CONTAINER_USER`.

The start script also installs your SSH public key for passwordless logins. By default it uses `~/.ssh/id_ed25519.pub`, generating an ed25519 keypair if it doesn't exist. Override the key path with `DEV_CONTAINER_SSH_KEY_PATH`.

### SSH into the container

```sh
script/dev-container/ssh
```

By default this connects to `developer@127.0.0.1:2222` using the installed key. Use `DEV_CONTAINER_SSH_PORT` or `DEV_CONTAINER_USER` to change it.

### Run the server, tests, and build (inside the container)

```sh
./script/server
./script/test
./script/cibuild
```

Or from macOS without SSH:

```sh
podman exec -it kingcounty-solutions-dev ./script/server
```

The Jekyll server binds to `0.0.0.0` in the container; open `http://127.0.0.1:4000` on macOS.

### Run Codex in the container

Provide the API key at runtime (never commit it):

```sh
export OPENAI_API_KEY="..."
podman exec -it -e OPENAI_API_KEY kingcounty-solutions-dev codex
```

Or via SSH:

```sh
script/dev-container/ssh
codex
```

### Stop and cleanup (optional)

```sh
script/dev-container/stop
podman rm -f kingcounty-solutions-dev
podman rmi kingcounty-solutions-dev
```
