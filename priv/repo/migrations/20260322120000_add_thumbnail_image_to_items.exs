defmodule ScientiaCognita.Repo.Migrations.AddThumbnailImageToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :thumbnail_image, :string
    end
  end
end
