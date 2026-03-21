defmodule ScientiaCognita.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # DATABASE_RESET=true: drop all tables, re-migrate, then seed.
    # Must run before the supervisor so the Repo isn't started yet
    # (Ecto.Migrator.with_repo starts it temporarily).
    if release?() and System.get_env("DATABASE_RESET") == "true" do
      ScientiaCognita.Release.reset()
    end

    children = [
      ScientiaCognitaWeb.Telemetry,
      ScientiaCognita.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:scientia_cognita, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:scientia_cognita, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ScientiaCognita.PubSub},
      {Oban, Application.fetch_env!(:scientia_cognita, Oban)},
      # Start to serve requests, typically the last entry
      ScientiaCognitaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ScientiaCognita.Supervisor]
    result = Supervisor.start_link(children, opts)

    ScientiaCognita.ObanTelemetry.attach()

    # Run seeds on every release boot — idempotent, creates owner if missing.
    if release?() do
      Task.start(fn -> ScientiaCognita.Release.seed() end)
    end

    # Ensure the storage bucket exists after the supervisor starts.
    Task.start(fn -> ScientiaCognita.Storage.ensure_bucket_exists() end)

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ScientiaCognitaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp release?, do: System.get_env("RELEASE_NAME") != nil

  defp skip_migrations?() do
    # Skip in dev (no RELEASE_NAME) or when DATABASE_RESET just ran all migrations.
    not release?() or System.get_env("DATABASE_RESET") == "true"
  end
end
