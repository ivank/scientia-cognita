defmodule ScientiaCognita.Repo.Migrations.AddFsmFieldsToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :text_color, :string
      add :bg_color, :string
      add :bg_opacity, :float
    end
  end
end
