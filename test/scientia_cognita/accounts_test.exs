defmodule ScientiaCognita.AccountsTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Accounts

  import ScientiaCognita.AccountsFixtures
  alias ScientiaCognita.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()

      {1, nil} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [hashed_password: "hashed"]
        )

      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "list_passkeys/1" do
    test "returns empty list when user has no passkeys" do
      user = user_fixture()
      assert Accounts.list_passkeys(user) == []
    end

    test "returns passkeys for the user, newest first" do
      user = user_fixture()
      p1 = passkey_fixture(user, label: "First")
      p2 = passkey_fixture(user, label: "Second")
      [latest, oldest] = Accounts.list_passkeys(user)
      assert latest.id == p2.id
      assert oldest.id == p1.id
    end

    test "does not return passkeys from other users" do
      user = user_fixture()
      other = user_fixture()
      passkey_fixture(other)
      assert Accounts.list_passkeys(user) == []
    end
  end

  describe "user_has_passkeys?/1" do
    test "returns false when user has no passkeys" do
      user = user_fixture()
      refute Accounts.user_has_passkeys?(user)
    end

    test "returns true when user has at least one passkey" do
      user = user_fixture()
      passkey_fixture(user)
      assert Accounts.user_has_passkeys?(user)
    end
  end

  describe "get_passkey_by_credential_id/1" do
    test "returns nil for unknown credential_id" do
      assert Accounts.get_passkey_by_credential_id("no_such_id") == nil
    end

    test "returns passkey with preloaded user" do
      user = user_fixture()
      passkey = passkey_fixture(user)
      result = Accounts.get_passkey_by_credential_id(passkey.credential_id)
      assert result.id == passkey.id
      assert result.user.id == user.id
    end
  end

  describe "register_passkey/2" do
    test "creates a passkey with valid attrs" do
      user = user_fixture()

      attrs = %{
        credential_id: :crypto.strong_rand_bytes(32),
        public_key: :crypto.strong_rand_bytes(77),
        sign_count: 0,
        authenticator_attachment: "platform",
        label: "Touch ID"
      }

      assert {:ok, passkey} = Accounts.register_passkey(user, attrs)
      assert passkey.user_id == user.id
      assert passkey.label == "Touch ID"
    end

    test "rejects duplicate credential_id" do
      user = user_fixture()
      existing = passkey_fixture(user)
      attrs = %{credential_id: existing.credential_id, public_key: :crypto.strong_rand_bytes(77)}
      assert {:error, changeset} = Accounts.register_passkey(user, attrs)
      assert %{credential_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "requires credential_id and public_key" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.register_passkey(user, %{})

      assert %{credential_id: ["can't be blank"], public_key: ["can't be blank"]} =
               errors_on(changeset)
    end
  end

  describe "update_passkey_label/2" do
    test "updates the label" do
      user = user_fixture()
      passkey = passkey_fixture(user)
      assert {:ok, updated} = Accounts.update_passkey_label(passkey, "My MacBook")
      assert updated.label == "My MacBook"
    end
  end

  describe "get_passkey_for_user/2" do
    test "returns passkey when owned by the user" do
      user = user_fixture()
      passkey = passkey_fixture(user)
      result = Accounts.get_passkey_for_user(user, passkey.id)
      assert result.id == passkey.id
    end

    test "returns nil when passkey belongs to another user" do
      user = user_fixture()
      other = user_fixture()
      passkey = passkey_fixture(other)
      assert Accounts.get_passkey_for_user(user, passkey.id) == nil
    end

    test "returns nil for unknown passkey id" do
      user = user_fixture()
      assert Accounts.get_passkey_for_user(user, -1) == nil
    end
  end

  describe "update_passkey_after_auth/3" do
    test "persists sign_count and last_used_at" do
      user = user_fixture()
      passkey = passkey_fixture(user)
      now = DateTime.utc_now(:second)
      updated = Accounts.update_passkey_after_auth(passkey, 42, now)
      assert updated.sign_count == 42
      assert updated.last_used_at == now
    end
  end

  describe "delete_passkey/2" do
    test "deletes an owned passkey" do
      user = user_fixture()
      passkey = passkey_fixture(user)
      assert {:ok, _} = Accounts.delete_passkey(user, passkey.id)
      assert Accounts.list_passkeys(user) == []
    end

    test "returns :not_found for unknown passkey" do
      user = user_fixture()
      assert {:error, :not_found} = Accounts.delete_passkey(user, -1)
    end

    test "returns :unauthorized when passkey belongs to another user" do
      user = user_fixture()
      other = user_fixture()
      passkey = passkey_fixture(other)
      assert {:error, :unauthorized} = Accounts.delete_passkey(user, passkey.id)
    end
  end

  describe "delete_user/1" do
    test "removes the user from the database" do
      user = user_fixture()
      assert {:ok, _} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "cascades to user tokens" do
      user = user_fixture()
      Accounts.generate_user_session_token(user)

      assert ScientiaCognita.Repo.exists?(
               from t in UserToken, where: t.user_id == ^user.id
             )

      Accounts.delete_user(user)

      refute ScientiaCognita.Repo.exists?(
               from t in UserToken, where: t.user_id == ^user.id
             )
    end

    test "cascades to passkeys" do
      user = user_fixture()
      passkey_fixture(user)
      assert Accounts.list_passkeys(user) != []

      Accounts.delete_user(user)

      # Passkey rows are gone — querying by user_id returns nothing
      assert ScientiaCognita.Repo.all(
               from p in ScientiaCognita.Accounts.UserPasskey,
                 where: p.user_id == ^user.id
             ) == []
    end
  end

  describe "export_user_data/1" do
    import ScientiaCognita.CatalogFixtures

    test "returns email and exported_at" do
      user = user_fixture()
      data = Accounts.export_user_data(user)

      assert data.email == user.email
      assert is_binary(data.exported_at)
      # ISO 8601
      assert {:ok, _, _} = DateTime.from_iso8601(data.exported_at)
    end

    test "catalogs is empty when user has no exports" do
      user = user_fixture()
      data = Accounts.export_user_data(user)
      assert data.catalogs == []
    end

    test "catalogs is empty when export has no album yet" do
      user = user_fixture()
      catalog = catalog_fixture()
      {:ok, _export} = ScientiaCognita.Photos.get_or_create_export(user, catalog)

      data = Accounts.export_user_data(user)
      assert data.catalogs == []
    end

    test "includes catalog name and google_photos_album_url when album exists" do
      user = user_fixture()
      catalog = catalog_fixture()
      {:ok, export} = ScientiaCognita.Photos.get_or_create_export(user, catalog)

      {:ok, _} =
        ScientiaCognita.Photos.set_export_status(export, "done",
          album_id: "album-123",
          album_url: "https://photos.google.com/album/album-123"
        )

      data = Accounts.export_user_data(user)

      assert [%{name: name, google_photos_album_url: url}] = data.catalogs
      assert name == catalog.name
      assert url == "https://photos.google.com/album/album-123"
    end

    test "only includes albums belonging to the requesting user" do
      user = user_fixture()
      other = user_fixture()
      catalog = catalog_fixture()

      {:ok, other_export} = ScientiaCognita.Photos.get_or_create_export(other, catalog)

      {:ok, _} =
        ScientiaCognita.Photos.set_export_status(other_export, "done",
          album_id: "album-other",
          album_url: "https://photos.google.com/album/album-other"
        )

      data = Accounts.export_user_data(user)
      assert data.catalogs == []
    end
  end
end
