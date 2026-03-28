defmodule ScientiaCognitaWeb.UserRegistrationController do
  use ScientiaCognitaWeb, :controller

  require Logger

  alias ScientiaCognita.Accounts
  alias ScientiaCognita.Accounts.User

  def new(conn, _params) do
    changeset = Accounts.change_user_email(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        case Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
          {:ok, _} ->
            conn
            |> put_flash(
              :info,
              "An email was sent to #{user.email}, please access it to confirm your account."
            )
            |> redirect(to: ~p"/users/log-in")

          {:error, reason} ->
            Logger.error("Failed to send login instructions to #{user.email}: #{inspect(reason)}")

            conn
            |> put_flash(
              :error,
              "Account created but we could not send the confirmation email. Please try logging in."
            )
            |> redirect(to: ~p"/users/log-in")
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
