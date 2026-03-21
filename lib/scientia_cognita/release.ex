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
