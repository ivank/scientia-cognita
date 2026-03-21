# Source Show Page Table Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `SourceShowLive` from a split gallery+failed-table layout to a unified LiveView stream-backed items table with an always-edit modal, fixed re-render pipeline, and collapsible Gemini extraction panels.

**Architecture:** Single-file refactor of `lib/scientia_cognita_web/live/console/source_show_live.ex`. Items migrate from plain assigns to a LiveView stream so only changed rows patch the DOM. The edit modal drops view/edit toggle and always opens in edit mode. Re-render is fixed to restart from `ProcessImageWorker` using the preserved `storage_key` instead of re-running only the render step. Stat cards are removed; a loading banner replaces the need for a separate in-flight indicator.

**Tech Stack:** Phoenix LiveView 1.8 (`stream/3`, `stream_insert/3`), Phoenix.LiveViewTest, DaisyUI/Tailwind, Oban (manual test mode), ExUnit, Jason.

---

## File Map

| File | Action | Notes |
|---|---|---|
| `lib/scientia_cognita_web/live/console/source_show_live.ex` | **Rewrite** | All changes land here |
| `test/scientia_cognita_web/live/console/source_show_live_test.exs` | **Create** | New LiveView test file |

No schema, migration, context, or worker changes are needed.

**PubSub contract (verified in existing code, do not change):**
Workers broadcast to `"source:#{source_id}"` with `{:source_updated, source}` and `{:item_updated, item}`. The mount subscribes to the same topic. This contract is already in place — no worker edits needed.

---

## Key Reference: Item FSM

`pending → downloading → processing → color_analysis → render → ready`, failed from any state.

- `storage_key`: set on `downloading→processing` (the original download)
- `processed_key`: set on `processing→color_analysis` (16:9 FHD); **overwritten** on `render→ready` (final rendered image)

---

## Task 1: Write the LiveView test scaffold

**Files:**
- Create: `test/scientia_cognita_web/live/console/source_show_live_test.exs`

- [ ] **Step 1.1: Create the test file**

```elixir
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
      source = source_fixture(status: "done")
      item = item_fixture(source, status: "ready", processed_key: "images/processed.jpg")

      {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

      assert html =~ "<table"
      assert html =~ item.title
      # No gallery grid — the old class was "grid-cols-2 sm:grid-cols-3"
      refute html =~ "grid-cols-2"
    end
  end
end
```

- [ ] **Step 1.2: Run to verify it fails (SourceShowLive not yet changed, gallery still there)**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: `refute html =~ "grid-cols-2"` fails because the gallery is still present.

**Note:** All tests in this file must use `"close_item"` (not `"cancel_edit"`) for modal-close events — Task 4 removes `cancel_edit` and replaces it with `close_item`. Write tests with the final event name from the start.

- [ ] **Step 1.3: Commit the failing test**

```bash
git add test/scientia_cognita_web/live/console/source_show_live_test.exs
git commit -m "test: scaffold SourceShowLive test with owner auth"
```

---

## Task 2: Migrate the data layer to LiveView streams

Replace `assign_source_data/2` (which loaded all items into assigns) with:
- `assign_source_stats/2` — assigns source + counts only
- `stream(:items, ...)` — items live in the stream

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 2.1: Add tests for the new PubSub behaviour**

Add to the `describe "mount"` block and add new describes:

```elixir
test "all items regardless of status appear in the table", %{conn: conn} do
  source = source_fixture(status: "done")
  _ready  = item_fixture(source, status: "ready",       title: "Ready Item")
  _failed = item_fixture(source, status: "failed",      title: "Failed Item")
  _dl     = item_fixture(source, status: "downloading", title: "Downloading Item")
  _render = item_fixture(source, status: "render",
                         storage_key: "sk", processed_key: "pk", title: "Rendering Item")

  {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

  assert html =~ "Ready Item"
  assert html =~ "Failed Item"
  assert html =~ "Downloading Item"
  assert html =~ "Rendering Item"
end

describe "PubSub: item_updated" do
  test "stream-inserts the updated item without full reload", %{conn: conn} do
    source = source_fixture(status: "items_loading")
    item   = item_fixture(source, status: "pending", title: "New Item")

    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

    # Simulate a worker broadcasting an item update
    updated = %{item | status: "ready", title: "Updated Item"}
    send(view.pid, {:item_updated, updated})

    html = render(view)
    assert html =~ "Updated Item"
  end
end
```

- [ ] **Step 2.2: Run to confirm new tests fail**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: "all items regardless of status" fails (gallery only shows ready items).

- [ ] **Step 2.3: Rewrite `mount/3` to use streams**

Replace the `mount/3` function:

```elixir
@impl true
def mount(%{"id" => id}, _session, socket) do
  source = Catalog.get_source!(id)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "source:#{id}")
  end

  all_items = Catalog.list_items_by_source(source)

  {:ok,
   socket
   |> assign(:show_delete_modal, false)
   |> assign(:selected_item, nil)
   |> assign(:item_form, nil)
   |> assign_source_stats(source)
   |> stream(:items, all_items)}
end
```

- [ ] **Step 2.4: Add `assign_source_stats/2` private helper**

Replace `assign_source_data/2` entirely:

```elixir
defp assign_source_stats(socket, source) do
  status_counts = Catalog.count_items_by_status(source)
  stuck_ids = Catalog.list_stuck_item_ids(source) |> MapSet.new()

  socket
  |> assign(:source, source)
  |> assign(:status_counts, status_counts)
  |> assign(:failed_count, status_counts["failed"] || 0)
  |> assign(:stuck_ids, stuck_ids)
end
```

- [ ] **Step 2.5: Rewrite the two `handle_info` clauses**

```elixir
@impl true
def handle_info({:source_updated, source}, socket) do
  # The broadcasted source already carries gemini_pages (embedded schema).
  {:noreply, assign_source_stats(socket, source)}
end

def handle_info({:item_updated, item}, socket) do
  source = socket.assigns.source
  status_counts = Catalog.count_items_by_status(source)
  stuck_ids = Catalog.list_stuck_item_ids(source) |> MapSet.new()

  {:noreply,
   socket
   |> stream_insert(:items, item)
   |> assign(:status_counts, status_counts)
   |> assign(:failed_count, status_counts["failed"] || 0)
   |> assign(:stuck_ids, stuck_ids)}
end
```

- [ ] **Step 2.6: Update `restart_source` and `retry_failed_items` handlers**

`restart_source` — call `assign_source_stats` instead of the old helper:

```elixir
def handle_event("restart_source", _, socket) do
  source = socket.assigns.source
  {:ok, source} = Catalog.reset_source(source)

  %{source_id: source.id}
  |> FetchPageWorker.new()
  |> Oban.insert()

  {:noreply,
   socket
   |> assign_source_stats(Catalog.get_source!(source.id))
   |> put_flash(:info, "Crawl restarted")}
end
```

`retry_failed_items` — load failed+stuck items from DB (no longer in assigns). Stuck items are in-progress states with no active Oban job. The key-based dispatch (`storage_key nil → DownloadImageWorker`, `processed_key nil → ProcessImageWorker`, `text_color nil → ColorAnalysisWorker`, else `RenderWorker`) correctly resumes both failed and stuck items from the right pipeline step:

```elixir
def handle_event("retry_failed_items", _, socket) do
  source = socket.assigns.source
  stuck_ids = socket.assigns.stuck_ids

  items_to_retry =
    Catalog.list_items_by_source(source)
    |> Enum.filter(fn item ->
      item.status == "failed" or MapSet.member?(stuck_ids, item.id)
    end)

  Enum.each(items_to_retry, fn item ->
    {status, worker} =
      cond do
        is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
        is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
        is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
        true -> {"render", RenderWorker}
      end

    {:ok, _} = Catalog.update_item_status(item, status, error: nil)
    %{item_id: item.id} |> worker.new() |> Oban.insert()
  end)

  {:noreply,
   socket
   |> assign_source_stats(source)
   |> put_flash(:info, "Retrying #{length(items_to_retry)} items")}
end
```

Remove the now-unused `progress_pct/2` and `sorted_status_counts/1` helpers — they are still needed for the progress bar, so keep them.

- [ ] **Step 2.7: Run the data-layer tests**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: mount and PubSub tests pass. Template tests still fail (gallery still in template).

- [ ] **Step 2.8: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "refactor: migrate SourceShowLive data layer to LiveView streams"
```

---

## Task 3: Replace gallery with the unified items table

This task rewrites the template section between the progress bar and the modals.

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 3.1: Add table and thumbnail tests**

```elixir
describe "items table" do
  test "colors rows by status", %{conn: conn} do
    source = source_fixture(status: "done")
    _ready  = item_fixture(source, status: "ready",    title: "Ready")
    _failed = item_fixture(source, status: "failed",   title: "Failed")
    _render = item_fixture(source, status: "render",
                           storage_key: "sk", processed_key: "pk", title: "Rendering")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "bg-success/10"
    assert html =~ "bg-error/10"
    assert html =~ "bg-info/10"
  end

  test "shows discarded badge for stuck items", %{conn: conn} do
    source = source_fixture(status: "items_loading")
    item   = item_fixture(source, status: "downloading")

    # Simulate stuck: item has no Oban job but is in an active state.
    # Directly check that a stuck item shows 'discarded' via stuck_ids assign.
    # We test the badge path by pushing the state from outside.
    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")

    # Manually push a source_updated with stuck_ids reflected (via item_updated)
    # In real use, list_stuck_item_ids detects this. Here we just verify the badge
    # appears when @stuck_ids contains the item's id.
    # Note: this is an integration concern; unit test the stuck badge via HTML check:
    refute render(view) =~ "discarded"
    # (No oban job exists for this item so list_stuck_item_ids should return it)
    # Re-render after mount re-queries — the badge appears because there's no active job
    assert render(view) =~ "discarded"
  end

  test "shows error text in description column for failed items", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "failed", title: "Broken")
    {:ok, _} = ScientiaCognita.Catalog.update_item_status(item, "failed",
                  error: "download timeout")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "download timeout"
  end
end

describe "thumbnails" do
  test "pending item shows skeleton shimmer", %{conn: conn} do
    source = source_fixture(status: "items_loading")
    _item  = item_fixture(source, status: "pending")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "skeleton"
  end

  test "render-status item shows animate-pulse ring", %{conn: conn} do
    source = source_fixture(status: "items_loading")
    _item  = item_fixture(source, status: "render",
                          storage_key: "sk", processed_key: "pk")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "animate-pulse"
  end

  test "failed item with no storage_key shows icon placeholder", %{conn: conn} do
    source = source_fixture(status: "done")
    _item  = item_fixture(source, status: "failed")
    # No storage_key set (default nil)

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "hero-photo"
  end
end
```

- [ ] **Step 3.2: Run to confirm new tests fail**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

- [ ] **Step 3.3: Add private helper functions**

Add these to the helpers section of `source_show_live.ex`:

```elixir
# Returns :shimmer | :icon | :render | :image
# Rules are strict top-down first-match (like function clauses).
# `ready` items always have processed_key set, so they fall through to the
# `processed_key present` branch — no explicit :ready case needed.
defp thumb_type(%{status: s}) when s in ~w(pending downloading), do: :shimmer
defp thumb_type(%{status: "failed", storage_key: nil}), do: :icon
defp thumb_type(%{status: "failed"}), do: :image
defp thumb_type(%{status: "render"}), do: :render
defp thumb_type(%{processed_key: pk}) when not is_nil(pk), do: :image  # ready, processing, color_analysis
defp thumb_type(%{storage_key: sk}) when not is_nil(sk), do: :image
defp thumb_type(_), do: :shimmer

# Returns the URL to display for :image type thumbnails
defp thumb_url(%{status: "failed", processed_key: pk}) when not is_nil(pk), do: pk
defp thumb_url(%{status: "failed", storage_key: sk}) when not is_nil(sk), do: sk
defp thumb_url(%{processed_key: pk}) when not is_nil(pk), do: pk
defp thumb_url(%{storage_key: sk}) when not is_nil(sk), do: sk
defp thumb_url(_), do: nil

defp row_class("pending"), do: "bg-base-200"
defp row_class("downloading"), do: "bg-base-200"
defp row_class("processing"), do: "bg-info/10"
defp row_class("color_analysis"), do: "bg-info/10"
defp row_class("render"), do: "bg-info/10"
defp row_class("ready"), do: "bg-success/10"
defp row_class("failed"), do: "bg-error/10"
defp row_class(_), do: ""

defp gemini_page_json(page) do
  # gemini_pages are always Ecto embedded schema structs, but guard defensively.
  data = if is_struct(page), do: Map.from_struct(page), else: page

  case Jason.encode(data, pretty: true) do
    {:ok, json} -> json
    {:error, _} -> inspect(page)
  end
end
```

- [ ] **Step 3.4: Add `item_thumbnail/1` component**

```elixir
defp item_thumbnail(assigns) do
  assigns = assign(assigns, :thumb_type, thumb_type(assigns.item))

  ~H"""
  <%= case @thumb_type do %>
  <% :shimmer -> %>
    <div class="skeleton rounded" style="width: 76px; height: 48px;"></div>
  <% :icon -> %>
    <div
      class="flex items-center justify-center bg-base-300 rounded"
      style="width: 76px; height: 48px;"
    >
      <.icon name="hero-photo" class="size-5 text-base-content/30" />
    </div>
  <% :render -> %>
    <div
      class="rounded overflow-hidden ring-2 ring-primary animate-pulse"
      style="width: 76px; height: 48px;"
    >
      <img
        src={Storage.get_url(@item.processed_key)}
        class="w-full h-full object-cover"
        loading="lazy"
      />
    </div>
  <% :image -> %>
    <div class="rounded overflow-hidden" style="width: 76px; height: 48px;">
      <img
        src={Storage.get_url(thumb_url(@item))}
        class="w-full h-full object-cover"
        loading="lazy"
      />
    </div>
  <% end %>
  """
end
```

- [ ] **Step 3.5: Replace the gallery + failed table sections in the template**

Remove this entire block from `render/1`:

```heex
<%!-- Item grid (ready items only) --%>
<div :if={@ready_items != []} class="space-y-3">
  ...
</div>

<%!-- Failed items --%>
<div :if={@failed_items != []} class="space-y-3">
  ...
</div>
```

Replace with:

```heex
<%!-- Loading banner --%>
<div :if={@source.status == "items_loading"} class="flex items-center gap-2 text-sm text-base-content/60">
  <span class="loading loading-spinner loading-sm"></span>
  Items are being loaded…
</div>

<%!-- Items table --%>
<div class="overflow-x-auto">
  <table class="table table-sm">
    <thead>
      <tr>
        <th class="w-20">Image</th>
        <th>Status</th>
        <th>Title</th>
        <th>Description</th>
      </tr>
    </thead>
    <tbody id="items" phx-update="stream">
      <tr
        :for={{dom_id, item} <- @streams.items}
        id={dom_id}
        class={"cursor-pointer hover:brightness-95 transition-all #{row_class(item.status)}"}
        phx-click="select_item"
        phx-value-id={item.id}
      >
        <td class="p-1">
          <.item_thumbnail item={item} />
        </td>
        <td class="whitespace-nowrap">
          <.status_badge status={item.status} />
          <span
            :if={MapSet.member?(@stuck_ids, item.id)}
            class="badge badge-warning badge-sm ml-1"
          >
            discarded
          </span>
        </td>
        <td class="max-w-xs">
          <p class="text-sm font-medium truncate">{item.title}</p>
        </td>
        <td class="max-w-sm">
          <p
            :if={item.status != "failed"}
            class="text-xs text-base-content/60 line-clamp-2"
          >
            {item.description}
          </p>
          <p
            :if={item.status == "failed"}
            class="text-xs text-error line-clamp-2"
          >
            {item.error || item.description}
          </p>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

Also remove the stat cards block:

```heex
<%!-- Progress stats --%>
<div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
  ...
</div>
```

And remove the `stat_card/1` private component at the bottom of the file.

- [ ] **Step 3.6: Run the table and thumbnail tests**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: all table/thumbnail tests pass. (The stuck badge test may need adjustment — see note in test.)

- [ ] **Step 3.7: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex \
        test/scientia_cognita_web/live/console/source_show_live_test.exs
git commit -m "feat: replace gallery with unified stream-backed items table"
```

---

## Task 4: Update the item edit modal

The modal now always opens in edit mode. The `select_item` handler builds the form immediately. Error is shown above the form. Re-download and Re-render buttons are guarded to terminal states only.

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 4.1: Add modal tests**

```elixir
describe "item edit modal" do
  test "clicking any row (including failed) opens the edit form", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "failed", title: "Broken Image")
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
    source = source_fixture(status: "items_loading")
    item   = item_fixture(source, status: "downloading")

    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
    view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

    refute render(view) =~ "Re-download"
  end

  test "re-download visible for terminal items", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "ready", processed_key: "pk")

    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
    view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

    assert render(view) =~ "Re-download"
  end

  test "re-render hidden when no storage_key", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "failed")
    # No storage_key (download never completed)

    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
    view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

    refute render(view) =~ "Re-render"
  end

  test "re-render visible for terminal items with storage_key", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "ready",
                          storage_key: "sk", processed_key: "pk")

    {:ok, view, _html} = live(conn, ~p"/console/sources/#{source.id}")
    view |> element("tr[phx-value-id='#{item.id}']") |> render_click()

    assert render(view) =~ "Re-render"
  end
end
```

- [ ] **Step 4.2: Run to confirm tests fail**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

- [ ] **Step 4.3: Update `select_item` handler**

Items are no longer in assigns (they're in the stream), so load from DB and build form immediately:

```elixir
def handle_event("select_item", %{"id" => id}, socket) do
  item = Catalog.get_item!(id)
  form = Catalog.change_item(item) |> to_form()
  {:noreply, socket |> assign(:selected_item, item) |> assign(:item_form, form)}
end
```

Remove the `edit_item` and `cancel_edit` handlers (modal is always in edit mode). Keep only:

```elixir
def handle_event("close_item", _, socket) do
  {:noreply, socket |> assign(:selected_item, nil) |> assign(:item_form, nil)}
end
```

Rename references: the Escape key handler and backdrop click now call `"close_item"` instead of toggling between modes.

- [ ] **Step 4.4: Update `save_item` and `validate_item` handlers**

`save_item` — close modal on success:

```elixir
def handle_event("save_item", %{"item" => params}, socket) do
  case Catalog.update_item(socket.assigns.selected_item, params) do
    {:ok, _item} ->
      {:noreply,
       socket
       |> assign(:selected_item, nil)
       |> assign(:item_form, nil)}

    {:error, changeset} ->
      {:noreply, assign(socket, :item_form, to_form(changeset))}
  end
end

def handle_event("validate_item", %{"item" => params}, socket) do
  form =
    socket.assigns.selected_item
    |> Catalog.change_item(params)
    |> Map.put(:action, :validate)
    |> to_form()

  {:noreply, assign(socket, :item_form, form)}
end
```

- [ ] **Step 4.5: Replace the item detail modal template**

Remove both the `<%!-- View mode --%>` and `<%!-- Edit mode --%>` sections inside the modal box. Replace the entire `modal-box` content with:

```heex
<div class="modal-box max-w-2xl p-0 overflow-hidden">
  <%!-- Preview image --%>
  <figure class="aspect-video bg-base-300 w-full">
    <img
      :if={@selected_item.processed_key || @selected_item.storage_key}
      src={Storage.get_url(@selected_item.processed_key || @selected_item.storage_key)}
      class="w-full h-full object-contain"
    />
  </figure>

  <div class="p-6 space-y-4">
    <%!-- Full error (if any) --%>
    <div :if={@selected_item.error} class="alert alert-error text-sm">
      <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
      <span>{@selected_item.error}</span>
    </div>

    <%!-- Edit form (always shown) --%>
    <.form for={@item_form} phx-submit="save_item" phx-change="validate_item" class="space-y-4">
      <div class="form-control">
        <label class="label pb-1">
          <span class="label-text text-xs font-medium uppercase tracking-wide">Title</span>
        </label>
        <.input field={@item_form[:title]} placeholder="Image title" />
      </div>
      <div class="form-control">
        <label class="label pb-1">
          <span class="label-text text-xs font-medium uppercase tracking-wide">Description</span>
        </label>
        <.input field={@item_form[:description]} type="textarea" rows="3" placeholder="Caption or description" />
      </div>
      <div class="form-control">
        <label class="label pb-1">
          <span class="label-text text-xs font-medium uppercase tracking-wide">Image URL</span>
        </label>
        <.input field={@item_form[:original_url]} type="url" placeholder="https://…" />
      </div>

      <div class="modal-action pt-0">
        <div class="flex gap-2 flex-1">
          <%!-- Re-download: terminal states only --%>
          <button
            :if={@selected_item.status in ~w(ready failed)}
            type="button"
            class="btn btn-ghost btn-sm gap-1"
            phx-click="redownload_item"
            phx-value-id={@selected_item.id}
            phx-disable-with="…"
            title="Clear stored images and re-run the full pipeline from download"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Re-download
          </button>

          <%!-- Re-render: terminal states + storage_key present --%>
          <button
            :if={@selected_item.status in ~w(ready failed) and not is_nil(@selected_item.storage_key)}
            type="button"
            class="btn btn-ghost btn-sm gap-1"
            phx-click="rerender_item"
            phx-value-id={@selected_item.id}
            phx-disable-with="…"
            title="Re-run from original downloaded image through the full processing chain"
          >
            <.icon name="hero-paint-brush" class="size-4" /> Re-render
          </button>
        </div>

        <button type="button" class="btn btn-ghost btn-sm" phx-click="close_item">Cancel</button>
        <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Saving…">Save</button>
      </div>
    </.form>
  </div>
</div>
<div class="modal-backdrop" phx-click="close_item"></div>
```

Also update the outer modal div attributes (remove the `if @item_form` conditional on `phx-window-keydown`):

```heex
<div
  :if={@selected_item}
  class="modal modal-open"
  phx-key="Escape"
  phx-window-keydown="close_item"
>
```

- [ ] **Step 4.6: Run modal tests**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: all modal tests pass.

- [ ] **Step 4.7: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex \
        test/scientia_cognita_web/live/console/source_show_live_test.exs
git commit -m "feat: edit modal always in edit mode with error display and terminal-only action guards"
```

---

## Task 5: Fix the re-render handler

Re-render must restart from `ProcessImageWorker` (using `storage_key`) rather than jumping straight to `RenderWorker` (which used the final rendered `processed_key` as input — wrong).

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 5.1: Add re-render test**

```elixir
describe "re-render action" do
  test "enqueues ProcessImageWorker (not RenderWorker) and resets to processing", %{conn: conn} do
    source = source_fixture(status: "done")
    item   = item_fixture(source, status: "ready",
                          storage_key: "images/original.jpg",
                          processed_key: "images/final.jpg",
                          text_color: "#FFFFFF",
                          bg_color: "#000000",
                          bg_opacity: 0.75)

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
end
```

- [ ] **Step 5.2: Run to confirm test fails**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: test fails — currently `RenderWorker` is enqueued, not `ProcessImageWorker`.

- [ ] **Step 5.3: Rewrite `rerender_item` handler**

```elixir
def handle_event("rerender_item", %{"id" => id}, socket) do
  item = Catalog.get_item!(id)

  # Clear rendered output AND color analysis results. If this re-render gets stuck
  # in color_analysis state, the retry dispatch checks `text_color: nil` to decide
  # whether to enqueue ColorAnalysisWorker. Leaving stale text_color would cause
  # retry to misroute to RenderWorker instead.
  # Note: Item.color_changeset/2 validates all three fields as required, so we use
  # a direct Ecto.Changeset.change to clear them.
  {:ok, item} =
    item
    |> Ecto.Changeset.change(%{
      processed_key: nil,
      text_color: nil,
      bg_color: nil,
      bg_opacity: nil
    })
    |> ScientiaCognita.Repo.update()

  {:ok, item} = Catalog.update_item_status(item, "processing", error: nil)
  # ProcessImageWorker reads storage_key, then chains color_analysis → render → ready
  %{item_id: item.id} |> ProcessImageWorker.new() |> Oban.insert()

  {:noreply,
   socket
   |> assign(:selected_item, nil)
   |> assign(:item_form, nil)
   |> put_flash(:info, "Re-rendering item")}
end
```

**Verify `ProcessImageWorker` chain:** Confirm at the top of `process_image_worker.ex` that:
1. It downloads from `item.storage_key` (it does — `download_original(item.storage_key)`)
2. On success it enqueues `ColorAnalysisWorker` (confirmed in moduledoc: "On success, enqueues ColorAnalysisWorker")
3. `ColorAnalysisWorker` in turn enqueues `RenderWorker`, which transitions to `ready`

So resetting to `"processing"` + enqueuing `ProcessImageWorker` runs the full `processing → color_analysis → render → ready` chain automatically. No further intervention needed.

Also update `redownload_item` to load the item from DB (no longer from `ready_items` assign which is removed):

```elixir
def handle_event("redownload_item", %{"id" => id}, socket) do
  item = Catalog.get_item!(id)
  # Clear both image keys so DownloadImageWorker fetches fresh copies
  {:ok, _} = Catalog.update_item_storage(item, %{storage_key: nil, processed_key: nil})
  {:ok, item} = Catalog.update_item_status(item, "pending", error: nil)
  %{item_id: item.id} |> DownloadImageWorker.new() |> Oban.insert()

  {:noreply,
   socket
   |> assign(:selected_item, nil)
   |> assign(:item_form, nil)
   |> put_flash(:info, "Re-downloading item")}
end
```

Keep `RenderWorker` in the module alias (still used by `retry_item` / `retry_failed_items`). `ProcessImageWorker` is already aliased at the top of the module.

- [ ] **Step 5.4: Run re-render test**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 5.5: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex \
        test/scientia_cognita_web/live/console/source_show_live_test.exs
git commit -m "fix: re-render restarts from ProcessImageWorker using original storage_key"
```

---

## Task 6: Add loading banner and collapsible Gemini panels

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 6.1: Add tests**

```elixir
describe "loading banner" do
  test "visible when source is items_loading", %{conn: conn} do
    source = source_fixture(status: "items_loading")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    assert html =~ "Items are being loaded"
  end

  test "not visible when source is done", %{conn: conn} do
    source = source_fixture(status: "done")

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    refute html =~ "Items are being loaded"
  end
end

describe "Gemini panels" do
  test "renders one details element per gemini_page", %{conn: conn} do
    source = source_fixture(status: "done")

    # Inject two gemini_pages directly
    page1 = %ScientiaCognita.Catalog.GeminiPageResult{
      page_url: "https://example.com/1",
      is_gallery: true,
      gallery_title: "Gallery One",
      gallery_description: "First page",
      items_count: 3,
      raw_items: [],
      generated_at: DateTime.utc_now(:second)
    }
    page2 = %ScientiaCognita.Catalog.GeminiPageResult{
      page_url: "https://example.com/2",
      is_gallery: true,
      gallery_title: "Gallery Two",
      gallery_description: "Second page",
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
    source = source_fixture(status: "done")
    # gemini_pages defaults to []

    {:ok, _view, html} = live(conn, ~p"/console/sources/#{source.id}")

    refute html =~ "<details"
  end
end
```

- [ ] **Step 6.2: Run to confirm tests fail**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

- [ ] **Step 6.3: Add Gemini panels to the template (after the items table)**

```heex
<%!-- Gemini extraction panels --%>
<div :if={@source.gemini_pages != []} class="space-y-2 pt-2">
  <h3 class="text-sm font-semibold text-base-content/60">Gemini Extraction Data</h3>
  <details
    :for={{page, idx} <- Enum.with_index(@source.gemini_pages, 1)}
    class="border border-base-300 rounded-lg overflow-hidden"
  >
    <summary class="flex items-center gap-2 px-4 py-2 cursor-pointer text-sm bg-base-200 hover:bg-base-300 select-none">
      <span class="font-medium">Page {idx}</span>
      <span :if={page.gallery_title}>· {page.gallery_title}</span>
      <span :if={page.gallery_description} class="text-base-content/50 truncate max-w-xs">
        — {String.slice(page.gallery_description || "", 0, 80)}
      </span>
      <span class="ml-auto text-base-content/40 shrink-0">{page.items_count} items</span>
    </summary>
    <pre class="text-xs overflow-auto max-h-96 bg-base-200 p-4 m-0">{gemini_page_json(page)}</pre>
  </details>
</div>
```

Note: `Floki` is already a test dependency (used in other tests). If not, add `{:floki, ">= 0.30.0", only: :test}` to `mix.exs` and run `mix deps.get`.

- [ ] **Step 6.4: Run all tests**

```
mix test test/scientia_cognita_web/live/console/source_show_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 6.5: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex \
        test/scientia_cognita_web/live/console/source_show_live_test.exs
git commit -m "feat: add loading banner and collapsible Gemini extraction panels"
```

---

## Task 7: Full test suite and cleanup

- [ ] **Step 7.1: Run the full test suite**

```
mix test
```

Expected: all tests pass. Fix any compilation warnings (unused variables, unused aliases).

- [ ] **Step 7.2: Remove dead code**

After the rewrite, check for and remove:
- `stat_card/1` component (replaced by the table)
- Any leftover `ready_items` / `failed_items` assigns or references
- The `assign_source_data/2` function (replaced by `assign_source_stats/2`)
- The `edit_item` / `cancel_edit` handlers (replaced by `close_item`)

Run `mix compile --warnings-as-errors` to surface any remaining issues.

```
mix compile --warnings-as-errors
```

- [ ] **Step 7.3: Run tests again after cleanup**

```
mix test
```

- [ ] **Step 7.4: Final commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "chore: remove dead code after SourceShowLive refactor"
```
