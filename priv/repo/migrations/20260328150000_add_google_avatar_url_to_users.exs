defmodule ScientiaCognita.Repo.Migrations.AddGoogleAvatarUrlToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_avatar_url, :string
    end
  end
end
