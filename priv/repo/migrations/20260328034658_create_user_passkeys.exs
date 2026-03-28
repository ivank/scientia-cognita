defmodule ScientiaCognita.Repo.Migrations.CreateUserPasskeys do
  use Ecto.Migration

  def change do
    create table(:user_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :authenticator_attachment, :string
      add :label, :string
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_passkeys, [:credential_id])
    create index(:user_passkeys, [:user_id])
  end
end
