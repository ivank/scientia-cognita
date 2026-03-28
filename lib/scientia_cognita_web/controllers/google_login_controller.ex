defmodule ScientiaCognitaWeb.GoogleLoginController do
  use ScientiaCognitaWeb, :controller

  plug Ueberauth

  alias ScientiaCognita.Accounts
  alias ScientiaCognitaWeb.UserAuth

  @doc """
  Ueberauth request phase — redirects to Google OAuth consent screen.
  Handled automatically by the Ueberauth plug.
  """
  def request(conn, _params), do: conn

  @doc """
  Ueberauth callback — find, link, or register the user, then log them in.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    google_id = auth.uid
    email = auth.info.email

    case find_or_create_user(google_id, email) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome!")
        |> UserAuth.log_in_user(user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not sign in with Google. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _}} = conn, _params) do
    conn
    |> put_flash(:error, "Google sign-in was cancelled or failed. Please try again.")
    |> redirect(to: ~p"/users/log-in")
  end

  # Found by google_id — direct login; otherwise fall through to email lookup
  defp find_or_create_user(google_id, email) do
    case Accounts.get_user_by_google_id(google_id) do
      %Accounts.User{} = user ->
        {:ok, user}

      nil ->
        find_or_register_by_email(google_id, email)
    end
  end

  # Try to find existing account by email and link google_id, or register new user
  defp find_or_register_by_email(google_id, email) do
    case Accounts.get_user_by_email(email) do
      %Accounts.User{} = user ->
        Accounts.link_google_account(user, google_id)

      nil ->
        Accounts.register_user_from_google(%{email: email, google_id: google_id})
    end
  end
end
