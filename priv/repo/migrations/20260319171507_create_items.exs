defmodule ScientiaCognita.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :title, :string, null: false
      add :description, :text
      add :author, :string
      add :copyright, :string
      add :original_url, :string
      add :original_image, :string
      add :processed_image, :string
      add :final_image, :string
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :source_id, references(:sources, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:items, [:source_id])
    create index(:items, [:status])
  end
end
