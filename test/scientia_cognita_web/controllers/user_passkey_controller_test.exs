defmodule ScientiaCognitaWeb.UserPasskeyControllerTest do
  use ScientiaCognitaWeb.ConnCase

  import Mox
  import ScientiaCognita.AccountsFixtures

  alias ScientiaCognita.Accounts

  setup :verify_on_exit!

  setup do
    %{user: user_fixture()}
  end

  # ------------------------------------------------------------------
  # Registration challenge
  # ------------------------------------------------------------------

  describe "GET /users/passkeys/challenge/register" do
    test "returns challenge JSON when authenticated", %{conn: conn, user: user} do
      expect(ScientiaCognita.MockWebAuthn, :new_registration_challenge, fn _opts ->
        build_fake_challenge(:create)
      end)

      conn = conn |> log_in_user(user) |> get(~p"/users/passkeys/challenge/register")

      assert %{"challenge" => _, "rp_id" => _, "user_id" => _, "user_name" => _} =
               json_response(conn, 200)
    end

    test "redirects to login when unauthenticated", %{conn: conn} do
      conn = get(conn, ~p"/users/passkeys/challenge/register")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  # ------------------------------------------------------------------
  # Registration (mocked WebAuthn)
  # ------------------------------------------------------------------

  describe "POST /users/passkeys (register)" do
    test "saves passkey and returns {ok: true} on valid attestation", %{conn: conn, user: user} do
      fake_challenge = build_fake_challenge(:create)
      fake_auth_data = build_fake_auth_data()

      ScientiaCognita.MockWebAuthn
      |> expect(:new_registration_challenge, fn _opts -> fake_challenge end)
      |> expect(:register, fn _att, _cdj, _challenge -> {:ok, {fake_auth_data, %{}}} end)

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/users/passkeys/challenge/register")

      conn =
        post(conn, ~p"/users/passkeys", %{
          "authenticatorAttachment" => "platform",
          "response" => %{
            "clientDataJSON" => Base.url_encode64("fake-cdj", padding: false),
            "attestationObject" => Base.url_encode64("fake-att", padding: false)
          }
        })

      assert %{"ok" => true} = json_response(conn, 200)
      assert [_passkey] = Accounts.list_passkeys(user)
    end

    test "returns error when WebAuthn verification fails", %{conn: conn, user: user} do
      fake_challenge = build_fake_challenge(:create)

      ScientiaCognita.MockWebAuthn
      |> expect(:new_registration_challenge, fn _opts -> fake_challenge end)
      |> expect(:register, fn _att, _cdj, _challenge -> {:error, :attestation_failed} end)

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/users/passkeys/challenge/register")

      conn =
        post(conn, ~p"/users/passkeys", %{
          "response" => %{
            "clientDataJSON" => Base.url_encode64("cdj", padding: false),
            "attestationObject" => Base.url_encode64("att", padding: false)
          }
        })

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  # ------------------------------------------------------------------
  # Authentication challenge
  # ------------------------------------------------------------------

  describe "GET /users/passkeys/challenge/authenticate" do
    test "returns challenge JSON without authentication", %{conn: conn} do
      expect(ScientiaCognita.MockWebAuthn, :new_authentication_challenge, fn _opts ->
        build_fake_challenge(:get)
      end)

      conn = get(conn, ~p"/users/passkeys/challenge/authenticate")
      assert %{"challenge" => _} = json_response(conn, 200)
    end
  end

  # ------------------------------------------------------------------
  # Authentication (mocked WebAuthn)
  # ------------------------------------------------------------------

  describe "POST /users/passkeys/authenticate" do
    test "authenticates and returns {ok, redirect} on valid assertion", %{conn: conn, user: user} do
      passkey = passkey_fixture(user, %{public_key: :erlang.term_to_binary(%{1 => 2, 3 => -7})})
      fake_challenge = build_fake_challenge(:get)
      fake_auth_data = build_fake_auth_data()

      ScientiaCognita.MockWebAuthn
      |> expect(:new_authentication_challenge, fn _opts -> fake_challenge end)
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, fake_auth_data}
      end)

      conn = get(conn, ~p"/users/passkeys/challenge/authenticate")

      conn =
        post(conn, ~p"/users/passkeys/authenticate", %{
          "rawId" => Base.url_encode64(passkey.credential_id, padding: false),
          "response" => %{
            "authenticatorData" => Base.url_encode64("auth-data", padding: false),
            "clientDataJSON" => Base.url_encode64("cdj", padding: false),
            "signature" => Base.url_encode64("sig", padding: false)
          }
        })

      assert %{"ok" => true, "redirect" => _} = json_response(conn, 200)
    end

    test "returns error when passkey not found", %{conn: conn} do
      expect(ScientiaCognita.MockWebAuthn, :new_authentication_challenge, fn _opts ->
        build_fake_challenge(:get)
      end)

      conn = get(conn, ~p"/users/passkeys/challenge/authenticate")

      conn =
        post(conn, ~p"/users/passkeys/authenticate", %{
          "rawId" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
          "response" => %{
            "authenticatorData" => Base.url_encode64("auth-data", padding: false),
            "clientDataJSON" => Base.url_encode64("cdj", padding: false),
            "signature" => Base.url_encode64("sig", padding: false)
          }
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns error when WebAuthn authentication fails", %{conn: conn, user: user} do
      passkey = passkey_fixture(user, %{public_key: :erlang.term_to_binary(%{1 => 2, 3 => -7})})
      fake_challenge = build_fake_challenge(:get)

      ScientiaCognita.MockWebAuthn
      |> expect(:new_authentication_challenge, fn _opts -> fake_challenge end)
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:error, :signature_invalid}
      end)

      conn = get(conn, ~p"/users/passkeys/challenge/authenticate")

      conn =
        post(conn, ~p"/users/passkeys/authenticate", %{
          "rawId" => Base.url_encode64(passkey.credential_id, padding: false),
          "response" => %{
            "authenticatorData" => Base.url_encode64("auth-data", padding: false),
            "clientDataJSON" => Base.url_encode64("cdj", padding: false),
            "signature" => Base.url_encode64("sig", padding: false)
          }
        })

      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  # ------------------------------------------------------------------
  # Delete passkey
  # ------------------------------------------------------------------

  describe "DELETE /users/passkeys/:id" do
    test "deletes owned passkey", %{conn: conn, user: user} do
      passkey = passkey_fixture(user)
      conn = conn |> log_in_user(user) |> delete(~p"/users/passkeys/#{passkey.id}")
      assert %{"ok" => true} = json_response(conn, 200)
      assert Accounts.list_passkeys(user) == []
    end

    test "returns 404 for unknown passkey", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/passkeys/99999")
      assert %{"error" => _} = json_response(conn, 404)
    end

    test "returns 403 when passkey belongs to another user", %{conn: conn, user: user} do
      other = user_fixture()
      passkey = passkey_fixture(other)
      conn = conn |> log_in_user(user) |> delete(~p"/users/passkeys/#{passkey.id}")
      assert %{"error" => _} = json_response(conn, 403)
    end
  end

  # ------------------------------------------------------------------
  # Update label
  # ------------------------------------------------------------------

  describe "PATCH /users/passkeys/:id" do
    test "updates label for owned passkey", %{conn: conn, user: user} do
      passkey = passkey_fixture(user)

      conn =
        conn
        |> log_in_user(user)
        |> patch(~p"/users/passkeys/#{passkey.id}", %{"label" => "My iPhone"})

      assert %{"ok" => true, "label" => "My iPhone"} = json_response(conn, 200)
    end

    test "returns 404 when passkey not found or not owned", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> patch(~p"/users/passkeys/99999", %{"label" => "X"})
      assert %{"error" => _} = json_response(conn, 404)
    end
  end

  # ------------------------------------------------------------------
  # Banner dismiss
  # ------------------------------------------------------------------

  describe "DELETE /users/passkeys/banner-dismiss" do
    test "sets session key and returns ok", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/passkeys/banner-dismiss")
      assert %{"ok" => true} = json_response(conn, 200)
    end
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp build_fake_challenge(type) do
    %Wax.Challenge{
      type: type,
      bytes: :crypto.strong_rand_bytes(32),
      origin: "http://localhost",
      rp_id: "localhost",
      token_binding_status: nil,
      issued_at: System.system_time(:second),
      allow_credentials: [],
      attestation: "none",
      silent_authentication_enabled: false
    }
  end

  defp build_fake_auth_data do
    credential_id = :crypto.strong_rand_bytes(32)

    fake_cose_key = %{
      1 => 2,
      3 => -7,
      -1 => 1,
      -2 => :crypto.strong_rand_bytes(32),
      -3 => :crypto.strong_rand_bytes(32)
    }

    %Wax.AuthenticatorData{
      rp_id_hash: :crypto.hash(:sha256, "localhost"),
      flag_user_present: true,
      flag_user_verified: false,
      flag_backup_eligible: false,
      flag_credential_backed_up: false,
      flag_attested_credential_data: true,
      flag_extension_data_included: false,
      sign_count: 0,
      attested_credential_data: %Wax.AttestedCredentialData{
        aaguid: <<0::128>>,
        credential_id: credential_id,
        credential_public_key: fake_cose_key
      },
      extensions: nil,
      raw_bytes: nil
    }
  end
end
