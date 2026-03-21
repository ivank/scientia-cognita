defmodule ScientiaCognita.Release do
  @moduledoc """
  Database tasks invoked from Application.start/2 on release boot.

  - Normal boot: Ecto.Migrator runs migrations, then seed/0 runs (idempotent).
  - DATABASE_RESET=true: reset/0 drops all tables, re-migrates, and seeds.
  """

  @app :scientia_cognita

  @spec setup() :: :ok
  def setup do
    migrate()
    seed()
    # reset()
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
