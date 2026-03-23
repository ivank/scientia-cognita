defmodule ScientiaCognita.Repo.Migrations.CreatePhotoExports do
  use Ecto.Migration

  def change do
    create table(:photo_exports) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :catalog_id, references(:catalogs, on_delete: :delete_all), null: false
      add :album_id, :string
      add :album_url, :string
      add :status, :string, null: false, default: "pending"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_exports, [:user_id, :catalog_id])
    create index(:photo_exports, [:user_id])
  end
end
