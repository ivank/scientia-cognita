defmodule ScientiaCognitaWeb.UserSettingsController do
  use ScientiaCognitaWeb, :controller

  alias ScientiaCognita.Accounts
  alias ScientiaCognitaWeb.UserAuth

  import ScientiaCognitaWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode
  plug :assign_settings_data

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings")

      changeset ->
        render(conn, :edit, email_changeset: %{changeset | action: :insert})
    end
  end

  def export_data(conn, _params) do
    user = conn.assigns.current_scope.user
    data = Accounts.export_user_data(user)
    json = Jason.encode!(data, pretty: true)
    filename = "scientia-cognita-data-#{Date.utc_today()}.json"

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, json)
  end

  def delete_account(conn, %{"confirm" => "delete my account"}) do
    user = conn.assigns.current_scope.user
    Accounts.delete_user(user)

    conn
    |> UserAuth.clear_user_session()
    |> put_flash(:info, "Your account has been permanently deleted.")
    |> redirect(to: ~p"/")
  end

  def delete_account(conn, _params) do
    conn
    |> put_flash(:error, "Please type \"delete my account\" to confirm deletion.")
    |> redirect(to: ~p"/users/settings")
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_settings_data(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:passkeys, Accounts.list_passkeys(user))
  end
end
