defmodule ScientiaCognita.Repo.Migrations.CreatePhotoExportItems do
  use Ecto.Migration

  def change do
    create table(:photo_export_items) do
      add :photo_export_id, references(:photo_exports, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_export_items, [:photo_export_id, :item_id])
    create index(:photo_export_items, [:photo_export_id])
  end
end
