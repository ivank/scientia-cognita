defmodule ScientiaCognita.Repo.Migrations.CreateCatalogItems do
  use Ecto.Migration

  def change do
    create table(:catalog_items) do
      add :catalog_id, references(:catalogs, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:catalog_items, [:catalog_id])
    create index(:catalog_items, [:item_id])
    create unique_index(:catalog_items, [:catalog_id, :item_id])
  end
end
