defmodule ScientiaCognita.Repo.Migrations.AddManualRotationToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :manual_rotation, :string, null: true
    end
  end
end
