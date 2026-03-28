defmodule ScientiaCognitaWeb.UserPasskeyController do
  use ScientiaCognitaWeb, :controller

  alias ScientiaCognita.Accounts
  alias ScientiaCognitaWeb.UserAuth

  # ------------------------------------------------------------------
  # Registration (authenticated)
  # ------------------------------------------------------------------

  def registration_challenge(conn, _params) do
    user = conn.assigns.current_scope.user

    challenge =
      webauthn().new_registration_challenge(
        attestation: "none",
        origin: origin()
      )

    conn
    |> put_session(:wax_registration_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      user_id: Base.url_encode64(Integer.to_string(user.id), padding: false),
      user_name: user.email,
      rp_id: rp_id(),
      rp_name: rp_name()
    })
  end

  def register(conn, params) do
    user = conn.assigns.current_scope.user
    challenge = get_session(conn, :wax_registration_challenge)
    conn = delete_session(conn, :wax_registration_challenge)

    with {:ok, attestation_object} <- decode_b64(params["response"]["attestationObject"]),
         {:ok, client_data_json} <- decode_b64(params["response"]["clientDataJSON"]),
         {:ok, {auth_data, _}} <- webauthn().register(attestation_object, client_data_json, challenge) do
      cred = auth_data.attested_credential_data
      label = build_label(auth_data)

      case Accounts.register_passkey(user, %{
             credential_id: cred.credential_id,
             public_key: :erlang.term_to_binary(cred.credential_public_key),
             sign_count: auth_data.sign_count,
             authenticator_attachment: params["authenticatorAttachment"],
             label: label
           }) do
        {:ok, _} ->
          json(conn, %{ok: true})

        {:error, changeset} ->
          if Keyword.has_key?(changeset.errors, :credential_id) do
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "This passkey is already registered."})
          else
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Could not save passkey. Please try again."})
          end
      end
    else
      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not verify passkey. Please try again."})
    end
  end

  # ------------------------------------------------------------------
  # Authentication (unauthenticated)
  # ------------------------------------------------------------------

  def authentication_challenge(conn, _params) do
    challenge = webauthn().new_authentication_challenge(origin: origin())

    conn
    |> put_session(:wax_authentication_challenge, challenge)
    |> json(%{challenge: Base.url_encode64(challenge.bytes, padding: false)})
  end

  def authenticate(conn, params) do
    challenge = get_session(conn, :wax_authentication_challenge)
    conn = delete_session(conn, :wax_authentication_challenge)

    with {:ok, credential_id} <- decode_b64(params["rawId"]),
         {:ok, auth_data} <- decode_b64(params["response"]["authenticatorData"]),
         {:ok, sig} <- decode_b64(params["response"]["signature"]),
         {:ok, client_data_json} <- decode_b64(params["response"]["clientDataJSON"]),
         passkey when not is_nil(passkey) <- Accounts.get_passkey_by_credential_id(credential_id),
         public_key <- :erlang.binary_to_term(passkey.public_key, [:safe]),
         {:ok, result} <-
           webauthn().authenticate(
             credential_id,
             auth_data,
             sig,
             client_data_json,
             challenge,
             [{credential_id, public_key}]
           ) do
      Accounts.update_passkey_after_auth(passkey, result.sign_count, DateTime.utc_now(:second))
      UserAuth.log_in_user(conn, passkey.user)
    else
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "No passkey found. Try another sign-in method."})

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Passkey verification failed."})
    end
  end

  # ------------------------------------------------------------------
  # Management (authenticated)
  # ------------------------------------------------------------------

  def update_label(conn, %{"id" => id, "label" => label}) do
    user = conn.assigns.current_scope.user

    case Accounts.get_passkey_for_user(user, String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Passkey not found."})

      passkey ->
        case Accounts.update_passkey_label(passkey, label) do
          {:ok, updated} -> json(conn, %{ok: true, label: updated.label})
          {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "Could not update label."})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    case Accounts.delete_passkey(user, String.to_integer(id)) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Passkey not found."})
      {:error, :unauthorized} -> conn |> put_status(:forbidden) |> json(%{error: "Not your passkey."})
    end
  end

  def dismiss_banner(conn, _params) do
    conn
    |> put_session(:passkey_banner_dismissed, true)
    |> json(%{ok: true})
  end

  # ------------------------------------------------------------------
  # Private helpers
  # ------------------------------------------------------------------

  defp webauthn, do: Application.get_env(:scientia_cognita, :webauthn)[:module]

  defp origin, do: Application.get_env(:scientia_cognita, :webauthn)[:origin]
  defp rp_id, do: Application.get_env(:scientia_cognita, :webauthn)[:rp_id]
  defp rp_name, do: Application.get_env(:scientia_cognita, :webauthn)[:rp_name]

  defp decode_b64(nil), do: {:error, :missing}
  defp decode_b64(str), do: Base.url_decode64(str, padding: false)

  defp build_label(authenticator_data) do
    with aaguid when not is_nil(aaguid) <- Wax.AuthenticatorData.get_aaguid(authenticator_data),
         {:ok, %{"description" => description}} when is_binary(description) <-
           Wax.Metadata.get_by_aaguid(aaguid) do
      description
    else
      _ -> "Passkey (added #{Date.utc_today()})"
    end
  end
end
