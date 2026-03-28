defmodule ScientiaCognitaWeb.UserSettingsControllerTest do
  use ScientiaCognitaWeb.ConnCase

  alias ScientiaCognita.Accounts
  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  setup :register_and_log_in_user

  describe "GET /users/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ "Settings"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "redirects if user is not in sudo mode", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end
  end

  describe "PUT /users/settings (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_email",
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "A link to confirm your email"

      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Settings"
      assert response =~ "must have the @ sign and no spaces"
    end
  end

  describe "GET /users/settings/confirm-email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully"

      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/settings/confirm-email/oops")
      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "GET /users/settings/export-data" do
    test "returns a JSON attachment with the user's email", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/settings/export-data")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "scientia-cognita-data-"
      assert disposition =~ ".json"

      body = Jason.decode!(conn.resp_body)
      assert body["email"] == user.email
      assert is_binary(body["exported_at"])
      assert is_list(body["catalogs"])
    end

    test "catalogs list is empty when user has no exports", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/export-data")
      body = Jason.decode!(conn.resp_body)
      assert body["catalogs"] == []
    end

    test "catalogs contains google_photos_album_url when album exists", %{
      conn: conn,
      user: user
    } do
      catalog = catalog_fixture()
      {:ok, export} = ScientiaCognita.Photos.get_or_create_export(user, catalog)

      {:ok, _} =
        ScientiaCognita.Photos.set_export_status(export, "done",
          album_id: "album-export-test",
          album_url: "https://photos.google.com/album/album-export-test"
        )

      conn = get(conn, ~p"/users/settings/export-data")
      body = Jason.decode!(conn.resp_body)

      assert [%{"name" => name, "google_photos_album_url" => url}] = body["catalogs"]
      assert name == catalog.name
      assert url == "https://photos.google.com/album/album-export-test"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/export-data")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/settings (delete account)" do
    test "deletes the account and redirects to home when confirmation matches", %{
      conn: conn,
      user: user
    } do
      conn = delete(conn, ~p"/users/settings", %{"confirm" => "delete my account"})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "permanently deleted"
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "clears the session after deletion", %{conn: conn} do
      conn = delete(conn, ~p"/users/settings", %{"confirm" => "delete my account"})
      assert get_session(conn, :user_token) == nil
    end

    test "does not delete account when confirmation text is wrong", %{conn: conn, user: user} do
      conn = delete(conn, ~p"/users/settings", %{"confirm" => "wrong text"})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "delete my account"
      assert Accounts.get_user!(user.id)
    end

    test "does not delete account when confirmation is missing", %{conn: conn, user: user} do
      conn = delete(conn, ~p"/users/settings", %{})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Accounts.get_user!(user.id)
    end

    test "redirects to login if user is not authenticated" do
      conn = build_conn()
      conn = delete(conn, ~p"/users/settings", %{"confirm" => "delete my account"})
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
