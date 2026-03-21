defmodule ScientiaCognita.Release do
  @moduledoc """
  Release tasks run outside of the application supervision tree.

  Called via fly.toml release_command before deploying a new version:

      [deploy]
        release_command = "/app/bin/scientia_cognita eval \\"ScientiaCognita.Release.setup()\\""
  """

  @app :scientia_cognita

  @spec setup() :: :ok
  def setup do
    migrate()
    seed()
  end

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @spec seed() :: :ok
  def seed do
    load_app()

    for repo <- repos() do
      Ecto.Migrator.with_repo(repo, fn _repo ->
        Code.eval_file("priv/repo/seeds.exs", File.cwd!())
      end)
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
