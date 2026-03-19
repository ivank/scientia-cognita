defmodule ScientiaCognita.Repo.Migrations.CreateCatalogs do
  use Ecto.Migration

  def change do
    create table(:catalogs) do
      add :name, :string, null: false
      add :description, :text
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:catalogs, [:slug])
  end
end
