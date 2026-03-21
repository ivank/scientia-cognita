defmodule ScientiaCognita.Repo.Migrations.FormalFsm do
  use Ecto.Migration

  def change do
    # SQLite >= 3.25 supports RENAME COLUMN; ecto_sqlite3 ships SQLite >= 3.35
    rename table(:sources), :gallery_title, to: :title
    rename table(:sources), :gallery_description, to: :description

    alter table(:sources) do
      add :gemini_pages, :text, default: "[]", null: false
    end
  end
end
