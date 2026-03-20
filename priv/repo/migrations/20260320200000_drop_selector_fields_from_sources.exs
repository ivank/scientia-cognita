defmodule ScientiaCognita.Repo.Migrations.DropSelectorFieldsFromSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      remove :selector_title, :string
      remove :selector_image, :string
      remove :selector_description, :string
      remove :selector_copyright, :string
      remove :selector_next_page, :string
    end
  end
end
