defmodule ScientiaCognita.Repo.Migrations.AddGooglePhotosMediaIdToPhotoExportItems do
  use Ecto.Migration

  def change do
    alter table(:photo_export_items) do
      add :google_photos_media_id, :string
    end
  end
end
