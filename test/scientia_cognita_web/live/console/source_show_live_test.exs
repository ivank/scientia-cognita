defmodule ScientiaCognitaWeb.Console.SourceShowLiveTest do
  use ScientiaCognitaWeb.ConnCase
  import Phoenix.LiveViewTest
  import ScientiaCognita.CatalogFixtures
  import ScientiaCognita.AccountsFixtures

  # Console routes require admin/owner role
  setup :owner_conn

  defp owner_conn(%{conn: conn}) do
    user = user_fixture()
    {:ok, user} = ScientiaCognita.Repo.update(Ecto.Changeset.change(user, role: "owner"))
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  describe "mount" do
    test "renders a table (not a gallery)", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item = item_fixture(source, %{status: "ready", processed_key: "images/processed.jpg"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "<table"
      assert html =~ item.title
      # No gallery grid — the old class was "grid-cols-2 sm:grid-cols-3"
      refute html =~ "grid-cols-2"
    end
  end
end
