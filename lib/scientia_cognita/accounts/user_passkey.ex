defmodule ScientiaCognita.Accounts.UserPasskey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_passkeys" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :authenticator_attachment, :string
    field :label, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, ScientiaCognita.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def creation_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:credential_id, :public_key, :sign_count, :authenticator_attachment, :label, :user_id])
    |> validate_required([:credential_id, :public_key, :user_id])
    |> unique_constraint(:credential_id)
  end

  def label_changeset(passkey, attrs) do
    cast(passkey, attrs, [:label])
  end
end
