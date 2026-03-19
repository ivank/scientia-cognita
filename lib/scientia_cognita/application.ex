defmodule ScientiaCognita.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ScientiaCognita.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ScientiaCognitaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
