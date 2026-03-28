> [!NOTE]
> This project is vibecoded from sctrath. Its a testbed to experiment with obra/superpowers and agentic development.
> Use with caution.

![Scientia Cognita logo](priv/static/images/logo.png)

# scientia cognita

Deployed at https://sc.ikerin.com

Serendipitous access to scientific knowledge — curate catalogs of images and serve them as a TV screensaver via Google Photos albums.

Browse and scrape sources with the help of Gemini AI, organise items into catalogs, and push them straight to Google Photos so your television always has something worth looking at.

![Explanations](priv/static/images/explanation.svg)

## Development

### Prerequisites

- Elixir 1.15+
- [libvips](https://www.libvips.org/) for image processing (`brew install vips` on macOS)
- Docker (for MinIO)

### 1. Start MinIO

MinIO provides S3-compatible object storage for images. A `docker-compose.yaml` is included that starts MinIO and creates the required bucket automatically:

```sh
docker compose up -d
```

MinIO will be available at `http://localhost:9000` (API) and `http://localhost:9001` (console).
Default credentials: `scientia-user` / `scientia-pass`.

### 2. Configure secrets

Copy the example secrets file and fill in your API keys:

```sh
cp config/dev.secret.exs.example config/dev.secret.exs
```

Edit `config/dev.secret.exs`:

- **Gemini API key** — get one at https://aistudio.google.com/app/apikey
- **Google OAuth credentials** — create an OAuth 2.0 Client ID (Web application) in the [Google Cloud Console](https://console.cloud.google.com), then add `http://localhost:4000/auth/google/callback` as an authorised redirect URI

### 3. Install, migrate, and seed

```sh
mix setup
```

This installs dependencies, creates and migrates the database, and seeds an owner account at `owner@scientia-cognita.local`.

To use a different email for the owner account:

```sh
OWNER_EMAIL=you@example.com mix setup
```

### 4. Start the server

```sh
mix phx.server
```

Open [`http://localhost:4000`](http://localhost:4000) in your browser. Log in via the magic-link flow — in development the email lands in the local mailbox at [`http://localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox).

The admin console is at [`http://localhost:4000/console`](http://localhost:4000/console).

---

## License

MIT © Ivan Kerin
