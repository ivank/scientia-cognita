defmodule ScientiaCognitaWeb.GoogleAuthController do
  use ScientiaCognitaWeb, :controller

  plug Ueberauth

  alias ScientiaCognita.Accounts

  @doc """
  Ueberauth request phase — redirects to Google OAuth consent screen.
  Handled automatically by the Ueberauth plug.
  """
  def request(conn, _params), do: conn

  @doc """
  Ueberauth callback — stores Google tokens on the current user and redirects back.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = conn.assigns.current_scope.user

    token_attrs = %{
      google_access_token: auth.credentials.token,
      google_refresh_token: auth.credentials.refresh_token,
      google_token_expires_at:
        auth.credentials.expires_at
        |> DateTime.from_unix!()
        |> DateTime.truncate(:second)
    }

    case Accounts.update_google_token(user, token_attrs) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Google Photos connected successfully.")
        |> redirect(to: return_path(conn))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to store Google credentials.")
        |> redirect(to: return_path(conn))
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _}} = conn, _params) do
    conn
    |> put_flash(:error, "Google authentication failed. Please try again.")
    |> redirect(to: return_path(conn))
  end

  defp return_path(conn) do
    get_session(conn, :google_auth_return_to) || "/"
  end
end
