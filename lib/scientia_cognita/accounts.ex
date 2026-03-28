defmodule ScientiaCognita.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias ScientiaCognita.Repo

  alias ScientiaCognita.Accounts.{User, UserPasskey, UserToken, UserNotifier}

  ## User management (admin/owner)

  @doc """
  Returns all users ordered by email.
  """
  def list_users do
    Repo.all(from u in User, order_by: [asc: u.email])
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for role changes.
  """
  def change_user_role(%User{} = user, attrs \\ %{}) do
    User.role_changeset(user, attrs)
  end

  @doc """
  Changes the role of `target` as performed by `actor`.

  Authorization rules:
  - owner can assign any role
  - admin can assign "user" or "admin" only
  - no one can demote the last owner
  """
  def set_role(%User{} = actor, %User{} = target, new_role) do
    with :ok <- authorize_role_change(actor, target, new_role),
         :ok <- check_last_owner(target, new_role) do
      target
      |> User.role_changeset(%{role: new_role})
      |> Repo.update()
    end
  end

  defp authorize_role_change(%User{role: "owner"}, _target, _new_role), do: :ok

  defp authorize_role_change(%User{role: "admin"}, _target, new_role)
       when new_role in ["user", "admin"],
       do: :ok

  defp authorize_role_change(_actor, _target, _new_role), do: {:error, :unauthorized}

  defp check_last_owner(%User{role: "owner"} = _target, new_role) when new_role != "owner" do
    owner_count = Repo.aggregate(from(u in User, where: u.role == "owner"), :count)

    if owner_count <= 1 do
      {:error, :last_owner}
    else
      :ok
    end
  end

  defp check_last_owner(_target, _new_role), do: :ok

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by their Google ID.
  """
  def get_user_by_google_id(google_id) when is_binary(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Registers a new user via Google OAuth (auto-confirmed, no password).
  """
  def register_user_from_google(attrs) do
    User.google_registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Links a Google ID (and optional avatar URL) to an existing user account.
  """
  def link_google_account(user, google_id, avatar_url \\ nil) do
    user
    |> User.google_id_changeset(%{google_id: google_id, google_avatar_url: avatar_url})
    |> Repo.update()
  end

  @doc """
  Updates the stored Google avatar URL for a user.
  """
  def update_google_avatar(%User{} = user, avatar_url) do
    user
    |> Ecto.Changeset.change(google_avatar_url: avatar_url)
    |> Repo.update()
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `ScientiaCognita.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `ScientiaCognita.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Account deletion / data export

  @doc """
  Permanently deletes the user and all associated data (tokens, passkeys, photo
  exports, export items) via database CASCADE. Irreversible.
  """
  def delete_user(%User{} = user), do: Repo.delete(user)

  @doc """
  Returns a minimal map suitable for JSON export (GDPR Article 20 portability).

  Includes only data the user directly provided or that was generated on their
  behalf: email and their Google Photos album links per catalog.
  """
  def export_user_data(%User{} = user) do
    alias ScientiaCognita.Photos.PhotoExport
    alias ScientiaCognita.Catalog.Catalog

    import Ecto.Query

    catalogs =
      Repo.all(
        from pe in PhotoExport,
          where: pe.user_id == ^user.id and not is_nil(pe.album_url),
          join: c in Catalog,
          on: c.id == pe.catalog_id,
          select: %{name: c.name, google_photos_album_url: pe.album_url}
      )

    %{
      exported_at: DateTime.utc_now(:second) |> DateTime.to_iso8601(),
      email: user.email,
      catalogs: catalogs
    }
  end

  ## Google OAuth tokens

  @doc """
  Stores Google OAuth tokens on the user after a successful OAuth callback.
  """
  def update_google_token(%User{} = user, attrs) do
    user
    |> User.google_token_changeset(attrs)
    |> Repo.update()
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Passkeys

  @doc "Returns all passkeys for a user, newest first."
  def list_passkeys(%User{} = user) do
    Repo.all(
      from p in UserPasskey,
        where: p.user_id == ^user.id,
        order_by: [desc: p.inserted_at, desc: p.id]
    )
  end

  @doc "Returns true if the user has at least one registered passkey."
  def user_has_passkeys?(%User{} = user) do
    Repo.exists?(from p in UserPasskey, where: p.user_id == ^user.id)
  end

  @doc "Finds a passkey by credential ID, preloading the associated user. Returns nil if not found."
  def get_passkey_by_credential_id(credential_id) when is_binary(credential_id) do
    Repo.one(from p in UserPasskey, where: p.credential_id == ^credential_id, preload: [:user])
  end

  @doc "Finds a passkey by id only if it belongs to the given user. Returns nil otherwise."
  def get_passkey_for_user(%User{} = user, passkey_id) do
    Repo.get_by(UserPasskey, id: passkey_id, user_id: user.id)
  end

  @doc "Registers a new passkey for the user."
  def register_passkey(%User{} = user, attrs) do
    %UserPasskey{user_id: user.id}
    |> UserPasskey.creation_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a passkey's label."
  def update_passkey_label(%UserPasskey{} = passkey, label) do
    passkey
    |> UserPasskey.label_changeset(%{label: label})
    |> Repo.update()
  end

  @doc """
  Deletes a passkey. Returns `{:error, :not_found}` if the passkey doesn't exist,
  `{:error, :unauthorized}` if it belongs to a different user.
  """
  def delete_passkey(%User{} = user, passkey_id) do
    case Repo.get(UserPasskey, passkey_id) do
      nil -> {:error, :not_found}
      %UserPasskey{user_id: uid} when uid != user.id -> {:error, :unauthorized}
      passkey -> Repo.delete(passkey)
    end
  end

  @doc "Updates sign_count and last_used_at after a successful passkey authentication."
  def update_passkey_after_auth(%UserPasskey{} = passkey, sign_count, last_used_at) do
    passkey
    |> Ecto.Changeset.change(sign_count: sign_count, last_used_at: last_used_at)
    |> Repo.update!()
  end
end
