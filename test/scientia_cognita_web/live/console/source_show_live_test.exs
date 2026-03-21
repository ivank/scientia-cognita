defmodule ScientiaCognitaWeb.Console.SourceShowLiveTest do
  use ScientiaCognitaWeb.ConnCase
  use Oban.Testing, repo: ScientiaCognita.Repo
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

      refute html =~ "bg-success/10"
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

  describe "item edit modal" do
    test "clicking any row (including failed) opens the edit form", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "failed", title: "Broken Image"})
      # Give item an error
      {:ok, item} = ScientiaCognita.Catalog.update_item_status(item, "failed", error: "bad url")

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      html = render(view)
      assert html =~ "modal modal-open"
      # Edit form is immediately visible (no view/edit toggle)
      assert html =~ ~s(phx-submit="save_item")
      # Full error shown
      assert html =~ "bad url"
    end

    test "re-download hidden for active (non-terminal) items", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      item   = item_fixture(source, %{status: "downloading"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      refute render(view) =~ "Re-download"
    end

    test "re-download visible for non-terminal item that has an error", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      item   = item_fixture(source, %{status: "downloading"})
      # Simulate partial-failure state: error set but status not yet failed
      {:ok, _item} = item |> Ecto.Changeset.change(%{error: "network timeout"}) |> ScientiaCognita.Repo.update()

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      assert render(view) =~ "Re-download"
    end

    test "re-download visible for terminal items", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready", processed_key: "pk"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      assert render(view) =~ "Re-download"
    end

    test "re-render hidden when no storage_key", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "failed"})
      # No storage_key (download never completed)

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      refute render(view) =~ "Re-render"
    end

    test "re-render visible for non-terminal item with error and storage_key", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      item   = item_fixture(source, %{status: "processing", storage_key: "sk"})
      # Simulate partial-failure state: error set but status not failed
      {:ok, _item} = item |> Ecto.Changeset.change(%{error: "color extraction failed"}) |> ScientiaCognita.Repo.update()

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      assert render(view) =~ "Re-render"
    end

    test "re-render visible for terminal items with storage_key", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready",
                            storage_key: "sk", processed_key: "pk"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      assert render(view) =~ "Re-render"
    end

    test "saving updates the row in the stream", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready", title: "Old Title", processed_key: "pk"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

      # Open modal
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      # Submit save with new title
      view
      |> form("form[phx-submit='save_item']", item: %{title: "New Title"})
      |> render_submit()

      html = render(view)
      assert html =~ "New Title"
      refute html =~ "Old Title"
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

  describe "loading banner" do
    test "visible when source is items_loading", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "Items are being loaded"
    end

    test "not visible when source is done", %{conn: conn} do
      source = source_fixture(%{status: "done"})

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      refute html =~ "Items are being loaded"
    end
  end

  describe "Gemini panels" do
    test "renders one details element per gemini_page", %{conn: conn} do
      source = source_fixture(%{status: "done"})

      # Inject two gemini_pages directly
      page1 = %ScientiaCognita.Catalog.GeminiPageResult{
        page_url: "https://example.com/1",
        is_gallery: true,
        gallery_title: "Gallery One",
        gallery_description: "First page",
        next_page_url: nil,
        items_count: 3,
        raw_items: [],
        generated_at: DateTime.utc_now(:second)
      }
      page2 = %ScientiaCognita.Catalog.GeminiPageResult{
        page_url: "https://example.com/2",
        is_gallery: true,
        gallery_title: "Gallery Two",
        gallery_description: "Second page",
        next_page_url: nil,
        items_count: 5,
        raw_items: [],
        generated_at: DateTime.utc_now(:second)
      }

      # `gemini_pages` is declared as `embeds_many :gemini_pages, GeminiPageResult`
      # in the Source schema, so put_embed is the correct API.
      {:ok, source} =
        source
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:gemini_pages, [page1, page2])
        |> ScientiaCognita.Repo.update()

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "Gallery One"
      assert html =~ "Gallery Two"
      assert html =~ "3 items"
      assert html =~ "5 items"
      # Two <details> elements
      assert html |> Floki.parse_document!() |> Floki.find("details") |> length() == 2
    end

    test "no Gemini section when gemini_pages is empty", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      # gemini_pages defaults to []

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      refute html =~ "<details"
    end
  end

  describe "re-download action" do
    test "keeps modal open and shows pending status after triggering", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready", processed_key: "pk"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()
      view |> element("button[phx-click='redownload_item']") |> render_click()

      html = render(view)
      # Modal stays open
      assert html =~ "modal modal-open"
      # Status badge updated to pending
      assert html =~ "pending"
    end
  end

  describe "re-render action" do
    test "enqueues ProcessImageWorker (not RenderWorker) and resets to processing", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready",
                            storage_key: "images/original.jpg",
                            processed_key: "images/final.jpg",
                            text_color: "#FFFFFF",
                            bg_color: "#000000",
                            bg_opacity: 0.75})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

      # Open modal
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()
      # Click re-render
      view |> element("button[phx-click='rerender_item']") |> render_click()

      # ProcessImageWorker should be in the Oban queue
      assert_enqueued(worker: ScientiaCognita.Workers.ProcessImageWorker,
                      args: %{"item_id" => item.id})

      # RenderWorker must NOT be enqueued
      refute_enqueued(worker: ScientiaCognita.Workers.RenderWorker,
                      args: %{"item_id" => item.id})

      # Item status reset to "processing", processed_key and color fields cleared
      reloaded = ScientiaCognita.Catalog.get_item!(item.id)
      assert reloaded.status == "processing"
      assert is_nil(reloaded.processed_key)
      assert is_nil(reloaded.text_color)
      assert is_nil(reloaded.bg_color)
      assert is_nil(reloaded.bg_opacity)
      assert reloaded.storage_key == "images/original.jpg"  # preserved
    end

    test "keeps modal open and shows processing status after triggering", %{conn: conn} do
      source = source_fixture(%{status: "done"})
      item   = item_fixture(source, %{status: "ready",
                            storage_key: "images/original.jpg",
                            processed_key: "images/final.jpg"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()
      view |> element("button[phx-click='rerender_item']") |> render_click()

      html = render(view)
      # Modal stays open
      assert html =~ "modal modal-open"
      # Status badge updated to processing
      assert html =~ "processing"
    end
  end

  describe "PubSub: item_updated with modal open" do
    test "updates selected_item preview when the open item is updated", %{conn: conn} do
      source = source_fixture(%{status: "items_loading"})
      item   = item_fixture(source, %{status: "pending"})

      {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
      view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

      # Simulate worker advancing the item to ready
      updated = %{item | status: "ready", processed_key: "images/done.jpg"}
      send(view.pid, {:item_updated, updated})

      html = render(view)
      # Modal still open, status badge updated
      assert html =~ "modal modal-open"
      assert html =~ "ready"
    end
  end
end
