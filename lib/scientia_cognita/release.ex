defmodule ScientiaCognita.Release do
  @moduledoc """
  Release tasks run outside of the application supervision tree.

  Called via fly.toml release_command before deploying a new version:

      [deploy]
        release_command = "/app/bin/scientia_cognita eval \\\"ScientiaCognita.Release.setup()\\\""

  Set DATABASE_RESET=true to drop and re-create the database, then seed.
  """

  @app :scientia_cognita

  @spec setup() :: :ok
  def setup do
    if System.get_env("DATABASE_RESET") == "true" do
      reset()
    else
      migrate()
    end
  end

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @spec reset() :: :ok
  def reset do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :down, all: true)
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    seed()
  end

  @spec seed() :: :ok
  def seed do
    load_app()

    for repo <- repos() do
      Ecto.Migrator.with_repo(repo, fn _repo ->
        seeds = Application.app_dir(@app, "priv/repo/seeds.exs")
        Code.eval_file(seeds)
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
