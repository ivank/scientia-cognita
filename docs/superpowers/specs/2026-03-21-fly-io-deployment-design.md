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
| `fly.toml` | New — app config, volume mount, release command, health check |
| `litefs.yml` | New — static primary lease, Fly volume data dir, exec start |
| `lib/scientia_cognita/release.ex` | New — `migrate/0` for release command |
| `config/prod.exs` | Modified — Swoosh API client |
| `config/runtime.exs` | Modified — Tigris endpoint, Mailgun adapter |

---

## Dockerfile

Multi-stage Alpine build:

**Stage 1 — builder** (`elixir:1.15-otp-26-alpine`)
- Install build deps: git, make, gcc, musl-dev, nodejs, npm
- `mix deps.get --only prod`
- `mix compile`
- `mix assets.deploy` (Tailwind + esbuild minify + phx.digest)
- `mix release`

**Stage 2 — runner** (`alpine`)
- Runtime packages: `libvips`, `fuse3`, `openssl`, `ncurses-libs`, `ca-certificates`
- Copy compiled release from builder stage
- Download `litefs` binary from GitHub releases and install to `/usr/local/bin/litefs`
- Copy `litefs.yml` to `/etc/litefs.yml`
- `ENTRYPOINT ["litefs", "mount"]`

The `image` hex library requires `libvips` at runtime. `fuse3` is required by LiteFS to create the FUSE filesystem.

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
  advertise-url: "http://${HOSTNAME}.vm.${FLY_APP_NAME}.internal:20202"

exec:
  - cmd: /app/bin/server
```

- The Fly volume is mounted at `/data` via `fly.toml`
- LiteFS stores internal state at `/data/litefs` (on the volume)
- The FUSE mount at `/litefs` is where the app reads/writes the database
- `DATABASE_PATH=/litefs/scientia_cognita.db` (set as Fly secret)
- `/app/bin/server` is the release wrapper script that sets `PHX_SERVER=true` and starts the app

---

## `fly.toml`

```toml
app = "<app-name>"
primary_region = "<region>"

[build]

[deploy]
  release_command = "/app/bin/scientia_cognita eval \"ScientiaCognita.Release.migrate()\""

[env]
  PHX_HOST = "<app-name>.fly.dev"
  PORT = "4000"

[http_service]
  internal_port = 4000
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

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

The release command runs migrations before the new version becomes live. If migrations fail, Fly aborts the deploy and the previous version stays up.

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

```elixir
config :ex_aws, :s3,
  scheme: "https://",
  host: "fly.storage.tigris.dev",
  region: "auto"

config :scientia_cognita, :storage,
  bucket: System.get_env("BUCKET_NAME") || System.get_env("AWS_S3_BUCKET") || "images"
```

No application code changes — `ex_aws` handles S3-compatible endpoints transparently.

---

## Mailgun Email Configuration

**`config/prod.exs`:**
```elixir
config :swoosh, :api_client, Swoosh.ApiClient.Req
```

**`config/runtime.exs`** (inside `if config_env() == :prod` block):
```elixir
config :scientia_cognita, ScientiaCognita.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: System.get_env("MAILGUN_API_KEY"),
  domain: "sc.ikiern.com"
```

Set via: `fly secrets set MAILGUN_API_KEY=<key>`

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
| `GEMINI_API_KEY` | Google AI Studio |
| `GOOGLE_CLIENT_ID` | Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google Cloud Console |
| `OWNER_EMAIL` | First owner account email |

---

## Startup Sequence

1. Container starts → LiteFS (`litefs mount`) becomes PID 1
2. LiteFS mounts Fly volume (`/data`) and exposes FUSE filesystem at `/litefs`
3. Fly runs `release_command` → migrations execute against `/litefs/scientia_cognita.db`
4. If migrations succeed, Fly starts the new container; otherwise deploy is aborted
5. LiteFS exec starts `/app/bin/server` → Phoenix boots on port 4000
6. Fly HTTP service proxies traffic, terminates TLS

---

## Out of Scope

- Multi-instance / LiteFS replica topology
- LiteFS Cloud (backup/restore)
- Custom domain TLS (handled via Fly `fly certs` separately)
- CI/CD pipeline (manual `fly deploy` for now)
