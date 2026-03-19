# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :scientia_cognita, :scopes,
  user: [
    default: true,
    module: ScientiaCognita.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ScientiaCognita.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :scientia_cognita,
  ecto_repos: [ScientiaCognita.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :scientia_cognita, ScientiaCognitaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ScientiaCognitaWeb.ErrorHTML, json: ScientiaCognitaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ScientiaCognita.PubSub,
  live_view: [signing_salt: "JrlUDSMu"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :scientia_cognita, ScientiaCognita.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  scientia_cognita: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  scientia_cognita: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# T04 — Oban background jobs (Lite engine for SQLite)
config :scientia_cognita, Oban,
  engine: Oban.Engines.Lite,
  repo: ScientiaCognita.Repo,
  queues: [
    default: 10,
    fetch: 5,
    process: 3,
    export: 5
  ]

# T05 — ExAws S3 (overridden per-env for MinIO in dev)
config :ex_aws,
  json_codec: Jason

# T06 — Gemini API (key set via GEMINI_API_KEY env var in runtime.exs)
config :scientia_cognita, :gemini,
  model: "gemini-2.0-flash-lite"

# T09 — Ueberauth Google OAuth (for Google Photos)
config :ueberauth, Ueberauth,
  providers: [
    google: {
      Ueberauth.Strategy.Google,
      [
        default_scope:
          "email profile https://www.googleapis.com/auth/photoslibrary",
        access_type: "offline",
        prompt: "consent"
      ]
    }
  ]

# T09 — Suppress Tesla deprecated builder warning (used by ueberauth_google)
config :tesla, disable_deprecated_builder_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
