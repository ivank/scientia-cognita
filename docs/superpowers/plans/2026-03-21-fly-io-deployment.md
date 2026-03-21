# Fly.io Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the Scientia Cognita Phoenix app for production deployment on Fly.io using LiteFS for SQLite persistence, Tigris for S3 image storage, and Mailgun for transactional email.

**Architecture:** LiteFS runs as PID 1 (static primary, no Consul), mounts a Fly persistent volume as a FUSE filesystem, and starts the Phoenix app sequentially after running database migrations. Tigris replaces MinIO as the S3-compatible image store with no application code changes. Mailgun replaces the Swoosh local adapter for production email.

**Tech Stack:** Fly.io, LiteFS v0.5.11, Tigris (S3-compatible), Mailgun, Swoosh, ex_aws, Alpine Linux, `image`/`vix` lib with `PLATFORM_PROVIDED_LIBVIPS`

**Spec:** `docs/superpowers/specs/2026-03-21-fly-io-deployment-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/scientia_cognita/release.ex` | Create | Run Ecto migrations from a release (called by LiteFS exec) |
| `config/runtime.exs` | Modify | Tigris S3 endpoint, Mailgun adapter, pool_size=2, updated env var comments |
| `.dockerignore` | Create | Exclude dev/build artifacts from Docker context |
| `Dockerfile` | Create | Multi-stage Alpine build: compile release + install libvips + LiteFS |
| `litefs.yml` | Create | LiteFS static primary config: Fly volume mount + sequential exec |
| `fly.toml` | Create | Fly app config: HTTP service, VM size, volume mount |

---

## Task 1: Release module

**Files:**
- Create: `lib/scientia_cognita/release.ex`
- Test: `test/scientia_cognita/release_test.exs`

This module is called by `litefs.yml`'s exec sequence to run Ecto migrations before the Phoenix server starts. It must work without a running application — `Application.load/1` loads the app config without starting any processes.

- [ ] **Step 1: Write the failing test**

Create `test/scientia_cognita/release_test.exs`:

```elixir
defmodule ScientiaCognita.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate/0 runs without error" do
    # Runs all pending migrations (none in test env since test setup already migrates)
    assert :ok == ScientiaCognita.Release.migrate()
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/scientia_cognita/release_test.exs
```

Expected: `** (UndefinedFunctionError) function ScientiaCognita.Release.migrate/0 is undefined`

- [ ] **Step 3: Create the release module**

Create `lib/scientia_cognita/release.ex`:

```elixir
defmodule ScientiaCognita.Release do
  @moduledoc """
  Release tasks run outside of the application supervision tree.

  Called by LiteFS exec sequence before starting the Phoenix server:

      exec:
        - cmd: /app/bin/scientia_cognita eval "ScientiaCognita.Release.migrate()"
        - cmd: /app/bin/server
  """

  @app :scientia_cognita

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
mix test test/scientia_cognita/release_test.exs
```

Expected: `1 test, 0 failures`

- [ ] **Step 5: Verify it compiles cleanly**

```bash
mix compile --warning-as-errors
```

Expected: no warnings, no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita/release.ex test/scientia_cognita/release_test.exs
git commit -m "feat: add Release.migrate/0 for LiteFS exec sequence"
```

---

## Task 2: Update runtime.exs for production

**Files:**
- Modify: `config/runtime.exs`

Four changes to the `if config_env() == :prod` block:
1. Update the required-variables comment to list `BUCKET_NAME` and Mailgun secrets
2. Change `pool_size` default from `"5"` to `"2"` (SQLite serializes writes; 2 is sufficient)
3. Replace the ex_aws credentials + storage config with Tigris-specific config
4. Add Mailgun adapter config

- [ ] **Step 1: Update the required-variables comment block**

In `config/runtime.exs`, find the comment block starting with `# Required environment variables summary (production):` (around line 42) and replace it:

```elixir
  # Required environment variables summary (production):
  #
  #   DATABASE_PATH         — absolute path to the SQLite database via LiteFS mount
  #                           e.g. /litefs/scientia_cognita.db
  #   SECRET_KEY_BASE       — 64-byte secret (run: mix phx.gen.secret)
  #   PHX_HOST              — public hostname, e.g. <app>.fly.dev
  #   PORT                  — HTTP port (default 4000)
  #   AWS_ACCESS_KEY_ID     — Tigris access key (auto-set by fly storage create)
  #   AWS_SECRET_ACCESS_KEY — Tigris secret key (auto-set by fly storage create)
  #   BUCKET_NAME           — Tigris bucket name (auto-set by fly storage create)
  #   MAILGUN_API_KEY       — Mailgun sending key
  #   MAILGUN_DOMAIN        — Mailgun sending domain, e.g. sc.ikiern.com
  #   GEMINI_API_KEY        — Google AI Studio key
  #   GOOGLE_CLIENT_ID      — OAuth client ID (Photos Library API)
  #   GOOGLE_CLIENT_SECRET  — OAuth client secret
  #   OWNER_EMAIL           — email address for the first owner account (seeds.exs)
```

- [ ] **Step 2: Change pool_size default**

Find this line:
```elixir
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
```

Replace with:
```elixir
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2")
```

- [ ] **Step 3: Replace the S3/storage config with Tigris config**

Find and replace the existing S3 block. The block to replace is:

```elixir
  # S3-compatible object storage (AWS S3 or MinIO in prod)
  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

  config :scientia_cognita, :storage, bucket: System.get_env("AWS_S3_BUCKET") || "images"
```

Replace with:

```elixir
  # S3-compatible object storage — Tigris (provisioned via fly storage create)
  config :ex_aws, :s3,
    scheme: "https://",
    host: "fly.storage.tigris.dev",
    region: "us-east-1"

  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    http_client: ExAws.Request.Hackney

  # BUCKET_NAME is auto-set by `fly storage create`; AWS_S3_BUCKET kept as fallback
  config :scientia_cognita, :storage,
    bucket: System.get_env("BUCKET_NAME") || System.get_env("AWS_S3_BUCKET") || "images"
```

Note: `region: "us-east-1"` is a required placeholder for AWS Signature V4 signing — Tigris accepts any region string. Do NOT use `"auto"`, which breaks signing.

- [ ] **Step 4: Add Mailgun mailer config**

At the end of the `if config_env() == :prod` block (before the closing `end`), add:

```elixir
  # Transactional email via Mailgun
  config :scientia_cognita, ScientiaCognita.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY"),
    domain: System.get_env("MAILGUN_DOMAIN") || "sc.ikiern.com"
```

- [ ] **Step 5: Verify the config compiles**

```bash
MIX_ENV=prod mix compile --warning-as-errors
```

Expected: no errors. (The prod compile will raise on missing env vars in runtime.exs — that is expected and fine; we are only checking for compile-time errors here.)

Actually, `runtime.exs` is not evaluated at compile time, so `mix compile` in prod env is safe. If it raises about `DATABASE_PATH`, run `DATABASE_PATH=/tmp/test.db SECRET_KEY_BASE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa MIX_ENV=prod mix compile`.

- [ ] **Step 6: Commit**

```bash
git add config/runtime.exs
git commit -m "config: update runtime.exs for Tigris S3, Mailgun, and LiteFS pool size"
```

---

## Task 3: Create .dockerignore

**Files:**
- Create: `.dockerignore`

Exclude files that bloat the Docker build context or expose secrets.

- [ ] **Step 1: Create `.dockerignore`**

```
# Build artifacts
_build/
deps/
.elixir_ls/
.git/

# Development database files
*.db
*.db-shm
*.db-wal

# Dev secrets (never in image)
config/dev.secret.exs
config/dev.secret.exs.example
.env
*.secret.*

# Assets source (compiled output is in priv/static)
assets/node_modules/

# Test artifacts
cover/

# Docs
docs/
README.md
```

- [ ] **Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore for Docker build context"
```

---

## Task 4: Create Dockerfile

**Files:**
- Create: `Dockerfile`

Multi-stage Alpine build. The key constraint: the `image`/`vix` library ships precompiled NIFs for glibc only. Alpine uses musl libc, so we must compile the NIF from source against the system libvips by setting `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`.

Before writing the Dockerfile, fetch the correct SHA256 for the LiteFS v0.5.11 linux/amd64 binary:

```bash
curl -sL https://github.com/superfly/litefs/releases/download/v0.5.11/litefs-v0.5.11-linux-amd64.tar.gz | sha256sum
```

Record the hash — you'll need it for the `RUN` step below. Replace `<SHA256>` in the Dockerfile with the actual value.

- [ ] **Step 1: Create `Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1

# ---- Stage 1: Build ----
FROM elixir:1.15-otp-26-alpine AS builder

# Build-time packages
# vips-dev and friends are needed to compile the vix NIF from source (PLATFORM_PROVIDED_LIBVIPS mode)
RUN apk add --no-cache \
  git \
  make \
  gcc \
  musl-dev \
  nodejs \
  npm \
  vips-dev \
  glib-dev \
  expat-dev \
  libpng-dev \
  libjpeg-turbo-dev \
  libwebp-dev

WORKDIR /app

# Use PLATFORM_PROVIDED_LIBVIPS so vix compiles against system libvips (musl-safe)
# rather than the bundled glibc precompiled NIF, which cannot load on Alpine
ENV VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS
ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Fetch and compile dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy config, priv (Gettext reads priv/gettext at compile time), and lib, then compile
COPY config config/
COPY priv priv/
COPY lib lib/
RUN mix compile

# Copy assets and build for production (assets.deploy writes digested files into priv/static)
COPY assets assets/
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Stage 2: Runtime ----
FROM alpine:3.19 AS runner

# Runtime packages
# libvips: required by the image/vix library at runtime
# fuse3: required by LiteFS for the FUSE filesystem
RUN apk add --no-cache \
  libvips \
  libgcc \
  fuse3 \
  openssl \
  ncurses-libs \
  ca-certificates

WORKDIR /app

# Copy the compiled release from builder
COPY --from=builder /app/_build/prod/rel/scientia_cognita ./

# Install LiteFS binary (pinned to v0.5.11)
# Verify SHA256 before using: run the fetch command above and replace <SHA256>
ARG LITEFS_SHA256=<SHA256>
RUN wget -qO /tmp/litefs.tar.gz \
  https://github.com/superfly/litefs/releases/download/v0.5.11/litefs-v0.5.11-linux-amd64.tar.gz \
  && echo "${LITEFS_SHA256}  /tmp/litefs.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/litefs.tar.gz -C /tmp \
  && mv /tmp/litefs /usr/local/bin/litefs \
  && chmod +x /usr/local/bin/litefs \
  && rm /tmp/litefs.tar.gz

# Copy LiteFS config
COPY litefs.yml /etc/litefs.yml

# LiteFS is PID 1; it mounts the FUSE filesystem and then starts the app via exec
ENTRYPOINT ["litefs", "mount"]
```

- [ ] **Step 2: Fetch the LiteFS SHA256 and substitute it**

Run:
```bash
curl -sL https://github.com/superfly/litefs/releases/download/v0.5.11/litefs-v0.5.11-linux-amd64.tar.gz | sha256sum
```

Replace `<SHA256>` in the `ARG LITEFS_SHA256=<SHA256>` line with the actual hex digest (e.g., `a1b2c3...`).

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "chore: add multi-stage Dockerfile with libvips and LiteFS"
```

---

## Task 5: Create litefs.yml

**Files:**
- Create: `litefs.yml`

LiteFS static primary config. The Fly volume is mounted at `/data` (configured in `fly.toml`). LiteFS stores its internal WAL data at `/data/litefs`. The FUSE mount at `/litefs` is what the app connects to via `DATABASE_PATH=/litefs/scientia_cognita.db`.

The exec sequence is sequential: migrations run first (after FUSE is ready), server starts second. This is why there is no `release_command` in `fly.toml` — the FUSE mount must already exist when migrations run.

- [ ] **Step 1: Create `litefs.yml`**

```yaml
# LiteFS configuration — static single-primary, no Consul required
#
# Fly volume (destination: /data in fly.toml) holds LiteFS internal state.
# The FUSE mount at /litefs is where the app reads/writes the SQLite database.
# DATABASE_PATH env var must be set to /litefs/scientia_cognita.db

fuse:
  dir: /litefs

data:
  dir: /data/litefs

lease:
  type: static
  primary: true

exec:
  # Step 1: run migrations (FUSE mount is ready at this point)
  - cmd: /app/bin/scientia_cognita eval "ScientiaCognita.Release.migrate()"
  # Step 2: start the Phoenix server
  - cmd: /app/bin/server
```

- [ ] **Step 2: Commit**

```bash
git add litefs.yml
git commit -m "chore: add litefs.yml for static primary SQLite replication"
```

---

## Task 6: Create fly.toml

**Files:**
- Create: `fly.toml`

The app name and region need to be filled in after running `fly launch` or manually chosen. The volume `scientia_cognita_data` is created by `fly volumes create` before first deploy.

- [ ] **Step 1: Create `fly.toml`**

```toml
# Fly.io app configuration for Scientia Cognita
# Run `fly launch` to create the app and fill in <app-name> and <region>,
# or set them manually and run `fly apps create <app-name>`.

app = "<app-name>"
primary_region = "<region>"

[build]

[env]
  # Public hostname used in Phoenix URL helpers and cookies
  PHX_HOST = "<app-name>.fly.dev"
  PORT = "4000"

[http_service]
  internal_port = 4000
  force_https = true
  # auto_stop_machines is effectively a no-op with min_machines_running = 1,
  # but documents intent: stop the machine when idle (useful if you lower min to 0 for dev)
  auto_stop_machines = "stop"
  auto_start_machines = true
  # Keep 1 machine running at all times to avoid cold-start latency from LiteFS FUSE remount
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 1000
    soft_limit = 800

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1

# Persistent volume for LiteFS internal data (SQLite WAL, etc.)
# Create before first deploy: fly volumes create scientia_cognita_data --region <region> --size 1
[[mounts]]
  source = "scientia_cognita_data"
  destination = "/data"
```

- [ ] **Step 2: Commit**

```bash
git add fly.toml
git commit -m "chore: add fly.toml for Fly.io deployment"
```

---

## Task 7: Verify local Docker build

This is a smoke test to catch Dockerfile errors before pushing to Fly.

- [ ] **Step 1: Build the image locally**

```bash
docker build -t scientia-cognita:local .
```

Expected: build completes without error. The vix NIF compilation step (inside `mix deps.compile`) will take a minute as it compiles C code. Watch for any error about libvips not found — if it appears, check that `vips-dev` is installed in the builder stage.

- [ ] **Step 2: If build fails on vix NIF, check the error**

Common failure mode: `ERROR: vips not found` — means `vips-dev` is missing or the Alpine package name changed. Verify with:
```bash
docker run --rm elixir:1.15-otp-26-alpine apk search vips
```

- [ ] **Step 3: Verify the release binary is present in the image**

```bash
docker run --rm --entrypoint /bin/sh scientia-cognita:local -c "ls /app/bin/"
```

Expected: `scientia_cognita` and `server` are listed.

- [ ] **Step 4: Verify litefs is present**

```bash
docker run --rm --entrypoint /bin/sh scientia-cognita:local -c "litefs --version"
```

Expected: `litefs version v0.5.11`

---

## Deployment Checklist (after all tasks pass)

These are manual steps run once from your local machine after the code is merged:

```bash
# 1. Create the Fly app (fill in your chosen app name and region)
fly apps create <app-name>

# 2. Create the persistent volume (1 GB is sufficient to start)
fly volumes create scientia_cognita_data --region <region> --size 1

# 3. Provision Tigris storage (auto-sets AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, BUCKET_NAME)
fly storage create

# 4. Set remaining secrets
fly secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  DATABASE_PATH=/litefs/scientia_cognita.db \
  MAILGUN_API_KEY=<your-mailgun-key> \
  MAILGUN_DOMAIN=sc.ikiern.com \
  GEMINI_API_KEY=<your-gemini-key> \
  GOOGLE_CLIENT_ID=<your-google-client-id> \
  GOOGLE_CLIENT_SECRET=<your-google-client-secret> \
  OWNER_EMAIL=<your-email>

# 5. Deploy
fly deploy

# 6. Tail logs to verify LiteFS mount + migrations + server start
fly logs
```

Expected log sequence:
```
litefs: mounting fuse filesystem
litefs: primary lease acquired
running migrations...
[info] Running ScientiaCognita.Repo.Migrations...
[info] == Running ... OK
[info] Running ScientiaCognitaWeb.Endpoint with Bandit...
```
