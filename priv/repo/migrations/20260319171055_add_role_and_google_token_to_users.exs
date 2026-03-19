defmodule ScientiaCognita.Repo.Migrations.AddRoleAndGoogleTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
      add :google_access_token, :text
      add :google_refresh_token, :text
      add :google_token_expires_at, :utc_datetime
    end
  end
end
