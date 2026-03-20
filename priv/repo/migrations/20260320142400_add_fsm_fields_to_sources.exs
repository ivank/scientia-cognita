defmodule ScientiaCognita.Repo.Migrations.AddFsmFieldsToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :raw_html, :text
      add :gallery_title, :string
      add :gallery_description, :string
      add :selector_title, :string
      add :selector_image, :string
      add :selector_description, :string
      add :selector_copyright, :string
      add :selector_next_page, :string
    end
  end
end
