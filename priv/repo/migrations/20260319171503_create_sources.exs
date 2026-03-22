defmodule ScientiaCognita.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :url, :string, null: false
      add :name, :string
      add :status, :string, null: false, default: "pending"
      add :next_page_url, :string
      add :pages_fetched, :integer, null: false, default: 0
      add :total_items, :integer, null: false, default: 0
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:url])
    create index(:sources, [:status])
  end
end
