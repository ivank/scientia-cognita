# Fly.io Deployment Design

**Date:** 2026-03-21
**App:** Scientia Cognita (Phoenix LiveView 1.8, SQLite, Oban Lite)
**Target:** Fly.io — single instance, LiteFS static primary, Tigris S3, Mailgun

---

## Overview

Deploy the Phoenix app as a Docker release to Fly.io. SQLite is persisted via LiteFS (static primary, no Consul) on a Fly volume. Image storage migrates from local MinIO to Tigris (S3-compatible). Transactional email via Mailgun using Swoosh.

---

## Files Created / Modified

| File | Action |
|---|---|
| `Dockerfile` | New — multi-stage build with libvips + LiteFS binary |
| `.dockerignore` | New — exclude dev/build artifacts |
| `fly.toml` | New — app config, volume mount, health check (no release_command) |
| `litefs.yml` | New — static primary lease, Fly volume data dir, sequential exec |
| `lib/scientia_cognita/release.ex` | New — `migrate/0` called from LiteFS exec sequence |
| `config/prod.exs` | No change — Swoosh API client already configured correctly |
| `config/runtime.exs` | Modified — Tigris endpoint, Mailgun adapter, pool_size, updated env var comments |

---

## Dockerfile

Multi-stage Alpine build using `PLATFORM_PROVIDED_LIBVIPS` mode for the `vix`/`image` NIF so the container uses the system libvips rather than a bundled glibc NIF (which would fail on Alpine's musl libc).

**Stage 1 — builder** (`elixir:1.15-otp-26-alpine`)

Build-time packages: `git`, `make`, `gcc`, `musl-dev`, `nodejs`, `npm`, `vips-dev`, `glib-dev`, `expat-dev`, `libpng-dev`, `libjpeg-turbo-dev`, `libwebp-dev`

Build steps:
- Set `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` (compile vix NIF against system libvips)
- `mix deps.get --only prod`
- `mix compile`
- `mix assets.deploy` (Tailwind + esbuild minify + phx.digest)
- `mix release`

**Stage 2 — runner** (`alpine`)

Runtime packages: `libvips`, `fuse3`, `openssl`, `ncurses-libs`, `ca-certificates`

- Copy compiled release from builder stage
- Download pinned `litefs` binary (v0.5.11) from GitHub releases, verify SHA256, install to `/usr/local/bin/litefs`
- Copy `litefs.yml` to `/etc/litefs.yml`
- `ENTRYPOINT ["litefs", "mount"]`

The `image` library requires libvips at runtime. `fuse3` is required by LiteFS for the FUSE filesystem. Setting `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` at build time ensures the compiled NIF links against the Alpine system libvips rather than a bundled glibc NIF that would fail to load on musl.

---

## LiteFS (`litefs.yml`)

```yaml
fuse:
  dir: /litefs

data:
  dir: /data/litefs

lease:
  type: static
  primary: true

exec:
  - cmd: /app/bin/scientia_cognita eval "ScientiaCognita.Release.migrate()"
  - cmd: /app/bin/server
```

Key points:
- The Fly volume is mounted at `/data` via `fly.toml`
- LiteFS stores internal state at `/data/litefs` (on the volume)
- The FUSE mount at `/litefs` is where the app reads/writes the database
- `DATABASE_PATH=/litefs/scientia_cognita.db` (set as Fly secret)
- LiteFS runs the exec commands **sequentially**: migrations first, then the server
- This replaces the `fly.toml` `release_command` pattern — migrations run after the FUSE mount is ready, avoiding volume contention between the release container and the running container
- `advertise-url` is omitted — not needed for a single static-primary instance
- `/app/bin/server` is the Phoenix release wrapper that sets `PHX_SERVER=true`

---

## `fly.toml`

```toml
app = "<app-name>"
primary_region = "<region>"

[build]

[env]
  PHX_HOST = "<app-name>.fly.dev"
  PORT = "4000"

[http_service]
  internal_port = 4000
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 1000
    soft_limit = 800

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1

[[mounts]]
  source = "scientia_cognita_data"
  destination = "/data"
```

Notes:
- No `release_command` — migrations are handled by LiteFS exec sequence
- `min_machines_running = 1` keeps the machine always running; `auto_stop_machines = "stop"` is effectively a no-op alongside it but documents intent. Set `min_machines_running = 0` only for staging/dev — it will cause multi-second cold-start latency while LiteFS remounts

---

## Release Module (`lib/scientia_cognita/release.ex`)

```elixir
defmodule ScientiaCognita.Release do
  @app :scientia_cognita

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
```

---

## Tigris S3 Configuration

Provisioned via `fly storage create`. Fly automatically sets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `BUCKET_NAME`
- `AWS_ENDPOINT_URL_S3` = `https://fly.storage.tigris.dev`

Changes to `config/runtime.exs` (inside `if config_env() == :prod` block):

The existing line:
```elixir
config :scientia_cognita, :storage, bucket: System.get_env("AWS_S3_BUCKET") || "images"
```
is **replaced** with:
```elixir
config :ex_aws, :s3,
  scheme: "https://",
  host: "fly.storage.tigris.dev",
  region: "us-east-1"

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  http_client: ExAws.Request.Hackney

config :scientia_cognita, :storage,
  bucket: System.get_env("BUCKET_NAME") || System.get_env("AWS_S3_BUCKET") || "images"
```

Notes:
- `region: "us-east-1"` is the correct placeholder for Tigris — `"auto"` is not a valid AWS region string and will break Signature V4 signing
- `http_client: ExAws.Request.Hackney` is explicit (hackney is in deps; auto-detection works but explicit is clearer)
- The existing `config :ex_aws` credentials block and `config :scientia_cognita, :storage` line in the prod section are replaced by this block
- `BUCKET_NAME` is the env var auto-set by Tigris provisioning; `AWS_S3_BUCKET` is kept as a fallback for manual configuration
- Also update the required-variables comment block at the top of the prod section in `runtime.exs` to list `BUCKET_NAME` instead of `AWS_S3_BUCKET`

---

## Mailgun Email Configuration

`config/prod.exs` already has `config :swoosh, api_client: Swoosh.ApiClient.Req` and `config :swoosh, local: false` — no changes needed.

**`config/runtime.exs`** (inside `if config_env() == :prod` block):
```elixir
config :scientia_cognita, ScientiaCognita.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: System.get_env("MAILGUN_API_KEY"),
  domain: System.get_env("MAILGUN_DOMAIN") || "sc.ikiern.com"
```

Set via: `fly secrets set MAILGUN_API_KEY=<key> MAILGUN_DOMAIN=sc.ikiern.com`

---

## SQLite Pool Size

In `config/runtime.exs` inside the prod block, override the default pool_size:
```elixir
config :scientia_cognita, ScientiaCognita.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2")
```

SQLite supports concurrent readers but serializes writes. Oban Lite also holds connections. A pool of 2 is sufficient and avoids "database is locked" contention. The existing `|| "5"` default is replaced with `|| "2"`.

---

## Secrets Summary

Set via `fly secrets set`:

| Secret | Source |
|---|---|
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `DATABASE_PATH` | `/litefs/scientia_cognita.db` |
| `AWS_ACCESS_KEY_ID` | Auto-set by `fly storage create` |
| `AWS_SECRET_ACCESS_KEY` | Auto-set by `fly storage create` |
| `BUCKET_NAME` | Auto-set by `fly storage create` |
| `MAILGUN_API_KEY` | Mailgun dashboard |
| `MAILGUN_DOMAIN` | `sc.ikiern.com` |
| `GEMINI_API_KEY` | Google AI Studio |
| `GOOGLE_CLIENT_ID` | Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google Cloud Console |
| `OWNER_EMAIL` | First owner account email |

---

## Startup Sequence

1. Container starts → LiteFS (`litefs mount`) becomes PID 1
2. LiteFS mounts Fly volume (`/data`) and exposes FUSE filesystem at `/litefs`
3. LiteFS exec (sequential): migrations run against `/litefs/scientia_cognita.db`
4. If migrations succeed, LiteFS exec: Phoenix starts on port 4000
5. Fly HTTP service proxies traffic, terminates TLS

Migration failures abort startup (the container exits), causing Fly to keep the previous version running.

---

## Out of Scope

- Multi-instance / LiteFS replica topology
- LiteFS Cloud (backup/restore)
- Custom domain TLS (handled via `fly certs` separately)
- CI/CD pipeline (manual `fly deploy` for now)
