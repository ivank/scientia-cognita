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
      refute html =~ "grid-cols-2 sm:grid-cols-3"
    end

    test "all items regardless of status appear in the table", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      _ready  = item_fixture(source, %{status: "ready",       title: "Ready Item"})
      _failed = item_fixture(source, %{status: "failed",      title: "Failed Item"})
      _dl     = item_fixture(source, %{status: "downloading", title: "Downloading Item"})
      _render = item_fixture(source, %{status: "render",
                             storage_key: "sk", processed_key: "pk", title: "Rendering Item"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "Ready Item"
      assert html =~ "Failed Item"
      assert html =~ "Downloading Item"
      assert html =~ "Rendering Item"
    end
  end

  describe "items table" do
    test "colors rows by status", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      _ready  = item_fixture(source, %{status: "ready",    title: "Ready"})
      _failed = item_fixture(source, %{status: "failed",   title: "Failed"})
      _render = item_fixture(source, %{status: "render",
                             storage_key: "sk", processed_key: "pk", title: "Rendering"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "bg-success/10"
      assert html =~ "bg-error/10"
      assert html =~ "bg-info/10"
    end

    test "shows error text in description column for failed items", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "failed", title: "Broken"})
      {:ok, _} = ScientiaCognita.Catalog.update_item_status(item, "failed",
                    error: "download timeout")

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "download timeout"
    end
  end

  describe "thumbnails" do
    test "pending item shows skeleton shimmer", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      _item  = item_fixture(source, %{status: "pending"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "skeleton"
    end

    test "render-status item shows animate-pulse ring", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      _item  = item_fixture(source, %{status: "render",
                            storage_key: "sk", processed_key: "pk"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "animate-pulse"
    end

    test "failed item with no storage_key shows icon placeholder", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      _item  = item_fixture(source, %{status: "failed"})
      # No storage_key set (default nil)

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "hero-photo"
    end
  end

  describe "PubSub: item_updated" do
    test "stream-inserts the updated item without full reload", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      item   = item_fixture(source, %{status: "pending", title: "New Item"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

      # Simulate a worker broadcasting an item update
      updated = %{item | status: "ready", title: "Updated Item"}
      send(view.pid, {:item_updated, updated})

      html = render(view)
      assert html =~ "Updated Item"
    end
  end
end
