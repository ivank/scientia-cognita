defmodule ScientiaCognita.Repo.Migrations.AddCopyrightToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :copyright, :string
    end
  end
end
