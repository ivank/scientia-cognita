defmodule ScientiaCognita.Repo.Migrations.AddImageAnalysisToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :image_analysis, :map
    end
  end
end
