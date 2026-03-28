defmodule ScientiaCognita.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(user admin owner)

  schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :role, :string, default: "user"
    field :google_id, :string
    field :google_avatar_url, :string
    field :google_access_token, :string, redact: true
    field :google_refresh_token, :string, redact: true
    field :google_token_expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
  end

  def google_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_access_token, :google_refresh_token, :google_token_expires_at])
    |> validate_required([:google_access_token, :google_token_expires_at])
  end

  def google_id_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_id, :google_avatar_url])
    |> validate_required([:google_id])
    |> unique_constraint(:google_id)
  end

  def google_registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :google_id, :google_avatar_url])
    |> validate_required([:email, :google_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, ScientiaCognita.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, ScientiaCognita.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

end
