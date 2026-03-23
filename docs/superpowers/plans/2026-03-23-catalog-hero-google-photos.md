# Catalog Hero Banner & Google Photos Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent per-user Google Photos sync tracking with a full-width hero banner on the catalog detail page showing sync state, per-item error badges, and album delete support.

**Architecture:** Two new DB tables (`photo_exports`, `photo_export_items`) owned by a new `Photos` context. `ExportAlbumWorker` is rewritten to persist state to those tables and support incremental sync. `CatalogShowLive` loads the user's export record on mount and renders a state-driven hero banner.

**Tech Stack:** Elixir/Phoenix 1.8, Phoenix LiveView 1.1, Ecto/SQLite, Oban, DaisyUI + Tailwind CSS, Heroicons, Ueberauth Google

**Spec:** `docs/superpowers/specs/2026-03-23-catalog-hero-google-photos-design.md`

---

## File Map

**Create:**
- `priv/repo/migrations/20260323100000_create_photo_exports.exs`
- `priv/repo/migrations/20260323100001_create_photo_export_items.exs`
- `lib/scientia_cognita/photos/photo_export.ex`
- `lib/scientia_cognita/photos/photo_export_item.ex`
- `lib/scientia_cognita/photos.ex`
- `lib/scientia_cognita/workers/delete_album_worker.ex`
- `test/scientia_cognita/photos_test.exs`
- `test/scientia_cognita/workers/delete_album_worker_test.exs`

**Modify:**
- `config/config.exs` — add `photoslibrary.edit.appcreateddata` OAuth scope
- `lib/scientia_cognita/workers/export_album_worker.ex` — rewrite to use Photos context
- `lib/scientia_cognita_web/live/page/catalog_show_live.ex` — hero banner, error badges, delete modal
- `test/support/fixtures/catalog_fixtures.ex` — add `catalog_fixture/1`

---

## Task 1: Database Migrations

**Files:**
- Create: `priv/repo/migrations/20260323100000_create_photo_exports.exs`
- Create: `priv/repo/migrations/20260323100001_create_photo_export_items.exs`

- [ ] **Step 1: Create photo_exports migration**

```elixir
# priv/repo/migrations/20260323100000_create_photo_exports.exs
defmodule ScientiaCognita.Repo.Migrations.CreatePhotoExports do
  use Ecto.Migration

  def change do
    create table(:photo_exports) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :catalog_id, references(:catalogs, on_delete: :delete_all), null: false
      add :album_id, :string
      add :album_url, :string
      add :status, :string, null: false, default: "pending"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_exports, [:user_id, :catalog_id])
    create index(:photo_exports, [:user_id])
  end
end
```

- [ ] **Step 2: Create photo_export_items migration**

```elixir
# priv/repo/migrations/20260323100001_create_photo_export_items.exs
defmodule ScientiaCognita.Repo.Migrations.CreatePhotoExportItems do
  use Ecto.Migration

  def change do
    create table(:photo_export_items) do
      add :photo_export_id, references(:photo_exports, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_export_items, [:photo_export_id, :item_id])
    create index(:photo_export_items, [:photo_export_id])
  end
end
```

- [ ] **Step 3: Run migrations**

```bash
mix ecto.migrate
```

Expected: Two new tables created, no errors.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260323100000_create_photo_exports.exs \
        priv/repo/migrations/20260323100001_create_photo_export_items.exs
git commit -m "feat: add photo_exports and photo_export_items migrations"
```

---

## Task 2: PhotoExport and PhotoExportItem Schemas

**Files:**
- Create: `lib/scientia_cognita/photos/photo_export.ex`
- Create: `lib/scientia_cognita/photos/photo_export_item.ex`

- [ ] **Step 1: Create PhotoExport schema**

```elixir
# lib/scientia_cognita/photos/photo_export.ex
defmodule ScientiaCognita.Photos.PhotoExport do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending running done failed deleted)

  schema "photo_exports" do
    field :album_id, :string
    field :album_url, :string
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :user, ScientiaCognita.Accounts.User
    belongs_to :catalog, ScientiaCognita.Catalog.Catalog

    has_many :photo_export_items, ScientiaCognita.Photos.PhotoExportItem

    timestamps(type: :utc_datetime)
  end

  def changeset(export, attrs) do
    export
    |> cast(attrs, [:user_id, :catalog_id, :album_id, :album_url, :status, :error])
    |> validate_required([:user_id, :catalog_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :catalog_id])
  end
end
```

- [ ] **Step 2: Create PhotoExportItem schema**

```elixir
# lib/scientia_cognita/photos/photo_export_item.ex
defmodule ScientiaCognita.Photos.PhotoExportItem do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending uploaded failed)

  schema "photo_export_items" do
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :photo_export, ScientiaCognita.Photos.PhotoExport
    belongs_to :item, ScientiaCognita.Catalog.Item

    timestamps(type: :utc_datetime)
  end

  def changeset(export_item, attrs) do
    export_item
    |> cast(attrs, [:photo_export_id, :item_id, :status, :error])
    |> validate_required([:photo_export_id, :item_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:photo_export_id, :item_id])
  end
end
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile --no-optional-deps 2>&1 | grep -E "error|warning" | head -20
```

Expected: No errors. Warnings about unused aliases are OK.

- [ ] **Step 4: Commit**

```bash
git add lib/scientia_cognita/photos/
git commit -m "feat: add PhotoExport and PhotoExportItem schemas"
```

---

## Task 3: Photos Context

**Files:**
- Create: `lib/scientia_cognita/photos.ex`
- Modify: `test/support/fixtures/catalog_fixtures.ex` — add `catalog_fixture/1`
- Create: `test/scientia_cognita/photos_test.exs`

- [ ] **Step 1: Write the failing tests**

First add a `catalog_fixture` to the existing catalog fixtures file. Open `test/support/fixtures/catalog_fixtures.ex` and add after the existing fixtures:

```elixir
  def catalog_fixture(attrs \\ %{}) do
    {:ok, catalog} =
      attrs
      |> Enum.into(%{
        name: "Test Catalog #{System.unique_integer([:positive])}"
      })
      |> ScientiaCognita.Catalog.create_catalog()

    catalog
  end
```

Then create the test file:

```elixir
# test/scientia_cognita/photos_test.exs
defmodule ScientiaCognita.PhotosTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Photos

  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  setup do
    user = user_fixture()
    source = source_fixture()
    catalog = catalog_fixture()
    item = item_fixture(source)
    %{user: user, catalog: catalog, item: item}
  end

  describe "get_export_for_user/2" do
    test "returns nil when no export exists", %{user: user, catalog: catalog} do
      assert Photos.get_export_for_user(user, catalog) == nil
    end

    test "returns the export when it exists", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert Photos.get_export_for_user(user, catalog).id == export.id
    end
  end

  describe "get_or_create_export/2" do
    test "creates a new export if none exists", %{user: user, catalog: catalog} do
      assert {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert export.user_id == user.id
      assert export.catalog_id == catalog.id
      assert export.status == "pending"
    end

    test "returns existing export without creating a duplicate", %{user: user, catalog: catalog} do
      {:ok, export1} = Photos.get_or_create_export(user, catalog)
      {:ok, export2} = Photos.get_or_create_export(user, catalog)
      assert export1.id == export2.id
    end
  end

  describe "set_export_status/3" do
    test "updates the export status", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, updated} = Photos.set_export_status(export, "running")
      assert updated.status == "running"
    end

    test "stores optional fields like album_id and album_url", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, updated} = Photos.set_export_status(export, "running", album_id: "abc123", album_url: "https://photos.google.com/album/abc123")
      assert updated.album_id == "abc123"
      assert updated.album_url == "https://photos.google.com/album/abc123"
    end
  end

  describe "set_item_uploaded/2 and list_uploaded_item_ids/1" do
    test "marks an item as uploaded and includes it in the id list", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_uploaded(export, item)
      assert item.id in Photos.list_uploaded_item_ids(export)
    end

    test "does not include failed items in uploaded id list", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "upload error")
      refute item.id in Photos.list_uploaded_item_ids(export)
    end
  end

  describe "set_item_failed/3" do
    test "records the error message on the export item", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, export_item} = Photos.set_item_failed(export, item, "timeout")
      assert export_item.status == "failed"
      assert export_item.error == "timeout"
    end

    test "updating a failed item to uploaded works (upsert)", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "first attempt failed")
      {:ok, _} = Photos.set_item_uploaded(export, item)
      assert item.id in Photos.list_uploaded_item_ids(export)
    end
  end

  describe "list_export_item_statuses/1" do
    test "returns a map of item_id to status/error", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "oops")
      statuses = Photos.list_export_item_statuses(export)
      assert statuses[item.id] == %{status: "failed", error: "oops"}
    end

    test "returns empty map when no items tracked", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert Photos.list_export_item_statuses(export) == %{}
    end
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/scientia_cognita/photos_test.exs 2>&1 | tail -20
```

Expected: Compile error — `ScientiaCognita.Photos` module not found.

- [ ] **Step 3: Implement the Photos context**

```elixir
# lib/scientia_cognita/photos.ex
defmodule ScientiaCognita.Photos do
  @moduledoc """
  Context for tracking per-user Google Photos export state.

  All functions are scoped to the authenticated user — never expose
  PhotoExport records across users.
  """

  import Ecto.Query

  alias ScientiaCognita.Repo
  alias ScientiaCognita.Photos.{PhotoExport, PhotoExportItem}

  @doc "Returns the user's export for this catalog, or nil."
  def get_export_for_user(user, catalog) do
    Repo.get_by(PhotoExport, user_id: user.id, catalog_id: catalog.id)
  end

  @doc "Returns the existing export, or inserts a new pending one."
  def get_or_create_export(user, catalog) do
    case get_export_for_user(user, catalog) do
      nil ->
        %PhotoExport{}
        |> PhotoExport.changeset(%{user_id: user.id, catalog_id: catalog.id, status: "pending"})
        |> Repo.insert()

      export ->
        {:ok, export}
    end
  end

  @doc """
  Updates the export's status. Pass optional keyword args to also update
  :album_id, :album_url, or :error at the same time.

  ## Examples

      set_export_status(export, "running")
      set_export_status(export, "done", album_url: url, album_id: id)
      set_export_status(export, "failed", error: "token expired")
  """
  def set_export_status(export, status, opts \\ []) do
    attrs = opts |> Enum.into(%{}) |> Map.put(:status, to_string(status))

    export
    |> PhotoExport.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns a list of item IDs that have been confirmed uploaded to Google Photos."
  def list_uploaded_item_ids(export) do
    Repo.all(
      from pei in PhotoExportItem,
        where: pei.photo_export_id == ^export.id and pei.status == "uploaded",
        select: pei.item_id
    )
  end

  @doc "Marks an item as successfully added to the Google Photos album (upsert)."
  def set_item_uploaded(export, item) do
    upsert_export_item(export, item, %{status: "uploaded", error: nil})
  end

  @doc "Records an upload failure for an item (upsert — safe to call multiple times)."
  def set_item_failed(export, item, error) do
    upsert_export_item(export, item, %{status: "failed", error: to_string(error)})
  end

  @doc """
  Returns a map of %{item_id => %{status: s, error: e}} for all tracked items
  in this export. Used by the LiveView to render error badges on the photo grid.
  """
  def list_export_item_statuses(export) do
    Repo.all(
      from pei in PhotoExportItem,
        where: pei.photo_export_id == ^export.id,
        select: {pei.item_id, %{status: pei.status, error: pei.error}}
    )
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp upsert_export_item(export, item, attrs) do
    base = %{photo_export_id: export.id, item_id: item.id}

    %PhotoExportItem{}
    |> PhotoExportItem.changeset(Map.merge(base, attrs))
    |> Repo.insert(
      on_conflict: {:replace, [:status, :error, :updated_at]},
      conflict_target: [:photo_export_id, :item_id]
    )
  end
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
mix test test/scientia_cognita/photos_test.exs
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/photos.ex \
        lib/scientia_cognita/photos/ \
        test/scientia_cognita/photos_test.exs \
        test/support/fixtures/catalog_fixtures.ex
git commit -m "feat: add Photos context with photo_exports and photo_export_items tracking"
```

---

## Task 4: Update Google OAuth Scope

**Files:**
- Modify: `config/config.exs` line 103

- [ ] **Step 1: Add the delete scope**

In `config/config.exs`, change line 103 from:

```elixir
        default_scope: "email profile https://www.googleapis.com/auth/photoslibrary.appendonly",
```

to:

```elixir
        default_scope: "email profile https://www.googleapis.com/auth/photoslibrary.appendonly https://www.googleapis.com/auth/photoslibrary.edit.appcreateddata",
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep error
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add config/config.exs
git commit -m "feat: add photoslibrary.edit.appcreateddata OAuth scope for album deletion"
```

---

## Task 5: Rewrite ExportAlbumWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/export_album_worker.ex`

The rewrite adds: Photos context integration, incremental sync (skipping already-uploaded items), per-item error tracking, user-scoped PubSub topic, and album_id persistence.

- [ ] **Step 1: Replace the entire worker**

```elixir
# lib/scientia_cognita/workers/export_album_worker.ex
defmodule ScientiaCognita.Workers.ExportAlbumWorker do
  @moduledoc """
  Oban worker that exports (or syncs) a catalog to a Google Photos album.

  Flow:
    1. Upsert a PhotoExport record and set status: running.
    2. Create the Google Photos album if album_id is nil.
    3. Determine which items are not yet uploaded (incremental sync).
    4. Upload each new item's bytes to get an upload token. Record failures.
    5. Batch-create media items in the album (50 per call).
       After each successful batch, mark those items as uploaded in the DB.
    6. Set export status: done, persist album_url, broadcast done.
    7. On crash: set export status: failed, broadcast failed.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Photos}
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"catalog_id" => catalog_id, "user_id" => user_id}}) do
    catalog = Catalog.get_catalog!(catalog_id)
    user = Accounts.get_user!(user_id)
    all_items = Catalog.list_catalog_items(catalog)
    token = user.google_access_token
    topic = "export:#{catalog_id}:#{user_id}"

    # 1. Upsert export and mark running
    {:ok, export} = Photos.get_or_create_export(user, catalog)
    {:ok, export} = Photos.set_export_status(export, "running")

    # 2. Create album in Google Photos if this is the first run
    export =
      if is_nil(export.album_id) do
        {:ok, album_id} = create_album(token, catalog.name)
        {:ok, export} = Photos.set_export_status(export, "running", album_id: album_id)
        export
      else
        export
      end

    # 3. Skip already-uploaded items (incremental sync)
    already_uploaded_ids = Photos.list_uploaded_item_ids(export)

    items_to_upload =
      all_items
      |> Enum.filter(& &1.final_image)
      |> Enum.reject(&(&1.id in already_uploaded_ids))

    total = length(items_to_upload)

    # 4. Upload bytes and collect {item, upload_token} pairs
    {successful_pairs, _} =
      items_to_upload
      |> Enum.with_index(1)
      |> Enum.reduce({[], 0}, fn {item, idx}, {acc, _} ->
        case upload_bytes(token, fetch_image(item), item.title) do
          {:ok, upload_token} ->
            Phoenix.PubSub.broadcast(
              ScientiaCognita.PubSub,
              topic,
              {:export_progress, %{uploaded: idx, total: total}}
            )

            {[{item, upload_token} | acc], idx}

          {:error, reason} ->
            Photos.set_item_failed(export, item, reason)
            {acc, idx}
        end
      end)

    # 5. Batch-create media items, mark each batch as uploaded in DB
    successful_pairs
    |> Enum.reverse()
    |> Enum.chunk_every(50)
    |> Enum.each(fn chunk ->
      batch_add_items(token, export.album_id, chunk)

      Enum.each(chunk, fn {item, _token} ->
        Photos.set_item_uploaded(export, item)
      end)
    end)

    # 6. Mark done, persist album_url, broadcast
    album_url = "https://photos.google.com/album/#{export.album_id}"
    {:ok, _} = Photos.set_export_status(export, "done", album_url: album_url)

    Phoenix.PubSub.broadcast(
      ScientiaCognita.PubSub,
      topic,
      {:export_done, %{album_url: album_url}}
    )

    :ok
  rescue
    e ->
      # catalog_id and user_id are local variables from the function head — use them directly.
      # Do NOT use Map.get(e, :catalog_id) — exception structs don't carry job args.
      try do
        if export = Photos.get_export_for_user(
             Accounts.get_user!(user_id),
             Catalog.get_catalog!(catalog_id)
           ) do
          Photos.set_export_status(export, "failed", error: Exception.message(e))
        end
      rescue
        _ -> :ok
      end

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        "export:#{catalog_id}:#{user_id}",
        {:export_failed, Exception.message(e)}
      )

      reraise e, __STACKTRACE__
  end

  # ---------------------------------------------------------------------------
  # Google Photos API helpers
  # ---------------------------------------------------------------------------

  defp create_album(token, name) do
    response =
      Req.post!(
        "#{@photos_base}/albums",
        json: %{album: %{title: name}},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> {:ok, response.body["id"]}
      _ -> {:error, inspect(response.body)}
    end
  end

  defp upload_bytes(token, binary, filename) do
    response =
      Req.post!(
        "#{@photos_base}/uploads",
        body: binary,
        headers: [
          {"Authorization", "Bearer #{token}"},
          {"Content-type", "application/octet-stream"},
          {"X-Goog-Upload-Protocol", "raw"},
          {"X-Goog-Upload-File-Name", "#{filename}.jpg"}
        ]
      )

    case response.status do
      200 -> {:ok, response.body}
      _ -> {:error, "HTTP #{response.status}: #{inspect(response.body)}"}
    end
  end

  defp batch_add_items(token, album_id, items_with_tokens) do
    new_media_items =
      Enum.map(items_with_tokens, fn {item, upload_token} ->
        %{
          description: item.title,
          simpleMediaItem: %{
            fileName: "#{item.title}.jpg",
            uploadToken: upload_token
          }
        }
      end)

    response =
      Req.post!(
        "#{@photos_base}/mediaItems:batchCreate",
        json: %{albumId: album_id, newMediaItems: new_media_items},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> :ok
      status -> raise "batchCreate failed with HTTP #{status}: #{inspect(response.body)}"
    end
  end

  defp fetch_image(item) do
    url = ItemImageUploader.url({item.final_image, item})
    Req.get!(url).body
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep -E "^error"
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita/workers/export_album_worker.ex
git commit -m "feat: rewrite ExportAlbumWorker with DB tracking, incremental sync, per-item error handling"
```

---

## Task 6: DeleteAlbumWorker

**Files:**
- Create: `lib/scientia_cognita/workers/delete_album_worker.ex`
- Create: `test/scientia_cognita/workers/delete_album_worker_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/scientia_cognita/workers/delete_album_worker_test.exs
defmodule ScientiaCognita.Workers.DeleteAlbumWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.Workers.DeleteAlbumWorker
  alias ScientiaCognita.Photos

  # NOTE: The HTTP call to Google Photos cannot be unit-tested here without a
  # mock adapter (Bypass or Req.Test plug). The test below covers the
  # authorization guard only. The full deletion flow is verified via manual
  # smoke test in Task 8.

  test "rejects job if export does not belong to the requesting user" do
    owner = user_fixture()
    attacker = user_fixture()
    catalog = catalog_fixture()
    {:ok, export} = Photos.get_or_create_export(owner, catalog)
    {:ok, export} = Photos.set_export_status(export, "done", album_id: "abc", album_url: "https://photos.google.com/album/abc")

    # attacker passes their own user_id but owner's export_id
    assert {:error, :unauthorized} =
      perform_job(DeleteAlbumWorker, %{photo_export_id: export.id, user_id: attacker.id})
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
mix test test/scientia_cognita/workers/delete_album_worker_test.exs 2>&1 | tail -10
```

Expected: Compile error — `DeleteAlbumWorker` not found.

- [ ] **Step 3: Implement DeleteAlbumWorker**

```elixir
# lib/scientia_cognita/workers/delete_album_worker.ex
defmodule ScientiaCognita.Workers.DeleteAlbumWorker do
  @moduledoc """
  Oban worker that deletes a Google Photos album created by this app.

  Attempts DELETE /v1/albums/:id. If the endpoint returns 404/405
  (not supported by this API version), falls back to removing all
  items from the album via batchRemoveMediaItems, leaving it empty.

  Authorization: verifies export.user_id == user_id before proceeding.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Accounts, Photos, Repo}
  alias ScientiaCognita.Photos.PhotoExport

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_export_id" => export_id, "user_id" => user_id}}) do
    export = Repo.get!(PhotoExport, export_id)
    user = Accounts.get_user!(user_id)

    # Authorization guard — never process another user's export
    if export.user_id != user.id do
      {:error, :unauthorized}
    else
      topic = "export:#{export.catalog_id}:#{user_id}"
      token = user.google_access_token

      case delete_or_clear_album(token, export.album_id) do
        :ok ->
          {:ok, _} = Photos.set_export_status(export, "deleted")

          Phoenix.PubSub.broadcast(
            ScientiaCognita.PubSub,
            topic,
            {:export_deleted, %{}}
          )

          :ok

        {:error, reason} ->
          Phoenix.PubSub.broadcast(
            ScientiaCognita.PubSub,
            topic,
            {:export_delete_failed, reason}
          )

          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Attempt DELETE; fall back to clearing items if DELETE is unsupported.
  defp delete_or_clear_album(token, album_id) do
    response =
      Req.delete!(
        "#{@photos_base}/albums/#{album_id}",
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      s when s in [200, 204] ->
        :ok

      s when s in [404, 405] ->
        # API doesn't support album deletion — clear all items instead
        require Logger
        Logger.warning("Google Photos album DELETE not supported (HTTP #{s}), falling back to clearing items")
        clear_album_items(token, album_id)

      _ ->
        {:error, "HTTP #{response.status}: #{inspect(response.body)}"}
    end
  end

  defp clear_album_items(token, album_id) do
    # List all media items in the album, then remove them
    case list_album_media_item_ids(token, album_id) do
      {:ok, []} ->
        :ok

      {:ok, media_item_ids} ->
        media_item_ids
        |> Enum.chunk_every(50)
        |> Enum.each(fn chunk ->
          Req.post!(
            "#{@photos_base}/albums/#{album_id}:batchRemoveMediaItems",
            json: %{mediaItemIds: chunk},
            headers: [{"Authorization", "Bearer #{token}"}]
          )
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_album_media_item_ids(token, album_id) do
    response =
      Req.post!(
        "#{@photos_base}/mediaItems:search",
        json: %{albumId: album_id, pageSize: 100},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 ->
        ids =
          (response.body["mediaItems"] || [])
          |> Enum.map(& &1["id"])

        {:ok, ids}

      _ ->
        {:error, "Could not list album items: HTTP #{response.status}"}
    end
  end
end
```

- [ ] **Step 4: Run the authorization guard test**

```bash
mix test test/scientia_cognita/workers/delete_album_worker_test.exs -t "rejects job" 2>&1 || mix test test/scientia_cognita/workers/delete_album_worker_test.exs 2>&1 | tail -15
```

Expected: The authorization test passes.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/delete_album_worker.ex \
        test/scientia_cognita/workers/delete_album_worker_test.exs
git commit -m "feat: add DeleteAlbumWorker for Google Photos album deletion"
```

---

## Task 7: CatalogShowLive — Mount + Hero Banner

**Files:**
- Modify: `lib/scientia_cognita_web/live/page/catalog_show_live.ex`

This task replaces the existing small header section with the full-width hero banner. The item grid and lightbox are unchanged here (Task 8).

- [ ] **Step 1: Replace catalog_show_live.ex with the updated version**

Replace the entire file:

```elixir
# lib/scientia_cognita_web/live/page/catalog_show_live.ex
defmodule ScientiaCognitaWeb.Page.CatalogShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :mount_current_scope}

  alias ScientiaCognita.{Catalog, Photos}
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8 space-y-6">
      <%!-- Breadcrumb --%>
      <div class="flex items-center gap-2 text-sm text-base-content/50">
        <.link navigate={~p"/"} class="hover:text-base-content">Catalogs</.link>
        <.icon name="hero-chevron-right" class="size-3" />
        <span>{@catalog.name}</span>
      </div>

      <%!-- Catalog title --%>
      <div>
        <h1 class="text-3xl font-bold">{@catalog.name}</h1>
        <p :if={@catalog.description} class="text-base-content/60 mt-1">{@catalog.description}</p>
      </div>

      <%!-- Hero Banner --%>
      <.hero_banner
        current_scope={@current_scope}
        export={@export}
        export_progress={@export_progress}
        export_total={@export_total}
        catalog={@catalog}
      />

      <%!-- Items grid --%>
      <div :if={@catalog_items == []} class="card bg-base-200 p-16 text-center">
        <.icon name="hero-photo" class="size-16 mx-auto text-base-content/30" />
        <p class="mt-4 text-base-content/50">No items in this catalog yet.</p>
      </div>

      <div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        <div
          :for={item <- @catalog_items}
          id={"item-#{item.id}"}
          class={[
            "card bg-base-200 overflow-hidden group cursor-pointer",
            item_failed?(@export_item_statuses, item.id) && "ring-2 ring-error"
          ]}
          phx-click="open_lightbox"
          phx-value-item-id={item.id}
        >
          <figure class="aspect-video bg-base-300 relative">
            <img
              :if={item.thumbnail_image || item.final_image}
              src={
                if item.thumbnail_image,
                  do: ItemImageUploader.url({item.thumbnail_image, item}),
                  else: ItemImageUploader.url({item.final_image, item})
              }
              class={[
                "w-full h-full object-cover group-hover:scale-105 transition-transform duration-300",
                item_failed?(@export_item_statuses, item.id) && "opacity-50"
              ]}
              loading="lazy"
            />
            <%!-- Failed badge --%>
            <div
              :if={item_failed?(@export_item_statuses, item.id)}
              class="absolute top-1.5 right-1.5 bg-error text-error-content text-[10px] font-bold px-1.5 py-0.5 rounded"
            >
              ⚠ FAILED
            </div>
            <%!-- Uploaded check --%>
            <div
              :if={item_uploaded?(@export_item_statuses, item.id)}
              class="absolute bottom-1.5 right-1.5 bg-success text-success-content rounded-full w-5 h-5 flex items-center justify-center"
            >
              <.icon name="hero-check" class="size-3" />
            </div>
          </figure>
          <div class="card-body p-3">
            <p class="text-xs font-medium truncate">{item.title}</p>
            <p :if={item.author} class="text-xs text-base-content/50 truncate">{item.author}</p>
          </div>
        </div>
      </div>
    </div>

    <%!-- Lightbox --%>
    <div
      :if={@lightbox_item}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_lightbox"
    >
      <div class="modal-box max-w-5xl w-full p-0 overflow-hidden">
        <figure class="aspect-video bg-base-300 relative overflow-hidden">
          <div
            :if={is_nil(@lightbox_item.thumbnail_image) and is_nil(@lightbox_item.final_image)}
            class="skeleton absolute inset-0 rounded-none"
          >
          </div>
          <img
            :if={@lightbox_item.thumbnail_image}
            src={ItemImageUploader.url({@lightbox_item.thumbnail_image, @lightbox_item})}
            class="absolute inset-0 w-full h-full object-contain"
          />
          <img
            :if={@lightbox_item.final_image}
            src={ItemImageUploader.url({@lightbox_item.final_image, @lightbox_item})}
            class="absolute inset-0 w-full h-full object-contain opacity-0 transition-opacity duration-700"
            onload={"this.classList.add('opacity-100'); var s=document.getElementById('lb-spinner-#{@lightbox_item.id}'); if(s) s.remove();"}
          />
          <div
            :if={@lightbox_item.final_image}
            id={"lb-spinner-#{@lightbox_item.id}"}
            class="absolute bottom-3 left-3 z-10"
          >
            <span class="loading loading-spinner loading-sm text-base-content/50"></span>
          </div>
        </figure>

        <%!-- Upload error banner (if any) --%>
        <div
          :if={item_error(@export_item_statuses, @lightbox_item.id)}
          class="bg-error/20 border-b border-error/30 px-4 py-2 flex items-center gap-2"
        >
          <.icon name="hero-exclamation-triangle" class="size-4 text-error flex-shrink-0" />
          <span class="text-sm text-error">
            Upload failed: {item_error(@export_item_statuses, @lightbox_item.id)}
          </span>
        </div>

        <div class="p-4 flex items-start justify-between gap-4">
          <div>
            <p class="font-semibold">{@lightbox_item.title}</p>
            <p :if={@lightbox_item.author} class="text-sm text-base-content/60">
              {@lightbox_item.author}
            </p>
            <p :if={@lightbox_item.copyright} class="text-xs text-base-content/40 mt-1">
              {@lightbox_item.copyright}
            </p>
          </div>
          <button class="btn btn-ghost btn-sm btn-circle shrink-0" phx-click="close_lightbox">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_lightbox"></div>
    </div>

    <%!-- Delete confirmation modal --%>
    <div :if={@show_delete_confirm} class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg">Delete album from Google Photos?</h3>
        <p class="py-4 text-base-content/70">
          This will permanently delete the album
          <strong>{@catalog.name}</strong>
          from your Google Photos library. The photos in this catalog will not be affected.
        </p>
        <div class="modal-action">
          <button class="btn btn-ghost" phx-click="cancel_delete_album">Cancel</button>
          <button class="btn btn-error" phx-click="confirm_delete_album">
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_delete_album"></div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Hero Banner Component
  # ---------------------------------------------------------------------------

  defp hero_banner(assigns) do
    ~H"""
    <%= cond do %>
      <% !@current_scope -> %>
        <div class="rounded-xl p-5 bg-slate-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-lock-closed" class="size-6 text-slate-300" />
              </div>
              <div>
                <div class="font-bold text-base">Save to your Google Photos</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  Sign in to save this catalog directly to your Google Photos library.
                </div>
              </div>
            </div>
            <.link href={~p"/users/log-in"} class="btn btn-primary gap-2 shrink-0">
              <.icon name="hero-key" class="size-4" /> Log in to save
            </.link>
          </div>
        </div>

      <% !has_google_token?(@current_scope) -> %>
        <div class="rounded-xl p-5 bg-slate-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-camera" class="size-6 text-amber-400" />
              </div>
              <div>
                <div class="font-bold text-base">Connect Google Photos</div>
                <div class="flex flex-wrap gap-3 mt-1 text-xs text-slate-400">
                  <span class="flex items-center gap-1">
                    <.icon name="hero-folder-plus" class="size-3" /> Create &amp; manage albums
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-arrow-up-tray" class="size-3" /> Upload photos
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-trash" class="size-3" /> Delete app albums
                  </span>
                </div>
              </div>
            </div>
            <.link href={~p"/auth/google"} class="btn btn-warning gap-2 shrink-0">
              <.icon name="hero-link" class="size-4" /> Connect Google Photos
            </.link>
          </div>
        </div>

      <% is_nil(@export) or @export.status == "deleted" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-slate-700 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-cloud" class="size-6 text-blue-400" />
              </div>
              <div>
                <div class="font-bold text-base">Not yet in your library</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  {length_or_zero(@catalog)} photos ready to save
                </div>
              </div>
            </div>
            <button
              class="btn btn-primary gap-2 shrink-0"
              phx-click="export_to_google_photos"
              phx-disable-with="Starting…"
            >
              <.icon name="hero-arrow-up-tray" class="size-4" /> Save to Google Photos
            </button>
          </div>
        </div>

      <% @export.status == "running" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-blue-900 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap mb-4">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-blue-950 flex items-center justify-center flex-shrink-0 animate-pulse">
                <.icon name="hero-clock" class="size-6 text-blue-400" />
              </div>
              <div>
                <div class="font-bold text-base">Uploading to Google Photos…</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  {@export_progress} of {@export_total} photos uploaded
                </div>
              </div>
            </div>
            <button class="btn btn-disabled btn-sm gap-2" disabled>
              <span class="loading loading-spinner loading-xs"></span> In progress…
            </button>
          </div>
          <div class="w-full bg-slate-700 rounded-full h-2.5 overflow-hidden">
            <div
              class="bg-gradient-to-r from-blue-500 to-blue-400 h-2.5 rounded-full transition-all duration-500"
              style={"width: #{progress_pct(@export_progress, @export_total)}%"}
            >
            </div>
          </div>
          <div class="flex justify-between mt-1.5 text-xs text-slate-500">
            <span>0</span><span>{@export_progress} / {@export_total}</span><span>{@export_total}</span>
          </div>
        </div>

      <% @export.status == "done" -> %>
        <div class="rounded-xl p-5 bg-emerald-950 border border-emerald-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-emerald-900 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-check-circle" class="size-6 text-emerald-400" />
              </div>
              <div>
                <div class="font-bold text-base">In your Google Photos library</div>
                <div class="text-sm text-emerald-400 mt-0.5">
                  {length_or_zero(@catalog)} photos
                  <a
                    :if={@export.album_url}
                    href={@export.album_url}
                    target="_blank"
                    class="underline ml-1"
                  >
                    View album ↗
                  </a>
                </div>
              </div>
            </div>
            <div class="flex gap-2 flex-wrap shrink-0">
              <button
                class="btn btn-sm gap-2 bg-emerald-900 border-emerald-700 text-emerald-300 hover:bg-emerald-800"
                phx-click="export_to_google_photos"
                phx-disable-with="Syncing…"
              >
                <.icon name="hero-arrow-path" class="size-4" /> Sync new items
              </button>
              <button
                class="btn btn-sm gap-2 bg-slate-900 border-red-900 text-red-400 hover:bg-red-950"
                phx-click="delete_album"
              >
                <.icon name="hero-trash" class="size-4" /> Delete album
              </button>
            </div>
          </div>
        </div>

      <% @export.status == "failed" -> %>
        <div class="rounded-xl p-5 bg-red-950 border border-red-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-red-900 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-exclamation-triangle" class="size-6 text-red-400" />
              </div>
              <div>
                <div class="font-bold text-base">Upload failed</div>
                <div class="text-sm text-red-400 mt-0.5">
                  {failed_item_count(@export_item_statuses)} items failed
                  <span :if={@export.error} class="ml-1 opacity-70">· {@export.error}</span>
                </div>
              </div>
            </div>
            <button
              class="btn btn-sm gap-2 bg-red-900 border-red-700 text-red-300 hover:bg-red-800"
              phx-click="export_to_google_photos"
              phx-disable-with="Retrying…"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Retry failed items
            </button>
          </div>
        </div>

      <% true -> %>
        <%!-- Fallback: shouldn't occur in practice --%>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    catalog = Catalog.get_catalog_by_slug!(slug)
    items = Catalog.list_catalog_items(catalog)

    {export, export_item_statuses} =
      if socket.assigns.current_scope do
        user = socket.assigns.current_scope.user
        export = Photos.get_export_for_user(user, catalog)
        statuses = if export, do: Photos.list_export_item_statuses(export), else: %{}
        {export, statuses}
      else
        {nil, %{}}
      end

    if socket.assigns.current_scope do
      user = socket.assigns.current_scope.user
      Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "export:#{catalog.id}:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, catalog.name)
     |> assign(:catalog, catalog)
     |> assign(:catalog_items, items)
     |> assign(:lightbox_item, nil)
     |> assign(:export, export)
     |> assign(:export_item_statuses, export_item_statuses)
     |> assign(:export_progress, 0)
     |> assign(:export_total, length(items))
     |> assign(:show_delete_confirm, false)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_lightbox", %{"item-id" => item_id}, socket) do
    item_id = String.to_integer(item_id)
    item = Enum.find(socket.assigns.catalog_items, &(&1.id == item_id))
    {:noreply, assign(socket, :lightbox_item, item)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_item, nil)}
  end

  def handle_event("export_to_google_photos", _params, socket) do
    user = socket.assigns.current_scope.user
    catalog = socket.assigns.catalog

    {:ok, _job} =
      %{catalog_id: catalog.id, user_id: user.id}
      |> ScientiaCognita.Workers.ExportAlbumWorker.new()
      |> Oban.insert()

    # NOTE: The hero banner will continue showing the previous state until the
    # worker starts and broadcasts {:export_progress, ...} (which triggers a
    # reload_export). This is a brief delay (< 1s in normal conditions). An
    # optimistic assign of a fake running export struct could reduce this flash,
    # but is not required for correctness.
    {:noreply,
     socket
     |> assign(:export_progress, 0)
     |> assign(:export_total, length(socket.assigns.catalog_items))}
  end

  def handle_event("delete_album", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  def handle_event("cancel_delete_album", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  def handle_event("confirm_delete_album", _params, socket) do
    export = socket.assigns.export
    user = socket.assigns.current_scope.user

    {:ok, _job} =
      %{photo_export_id: export.id, user_id: user.id}
      |> ScientiaCognita.Workers.DeleteAlbumWorker.new()
      |> Oban.insert()

    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:export_progress, %{uploaded: n, total: t}}, socket) do
    {:noreply, socket |> assign(:export_progress, n) |> assign(:export_total, t)}
  end

  def handle_info({:export_done, _}, socket) do
    {:noreply, reload_export(socket)}
  end

  def handle_info({:export_failed, _reason}, socket) do
    socket = reload_export(socket)
    {:noreply, put_flash(socket, :error, "Export failed. Check failed items below.")}
  end

  def handle_info({:export_deleted, _}, socket) do
    {:noreply, reload_export(socket)}
  end

  def handle_info({:export_delete_failed, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Could not delete album: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_export(socket) do
    user = socket.assigns.current_scope.user
    catalog = socket.assigns.catalog
    export = Photos.get_export_for_user(user, catalog)
    statuses = if export, do: Photos.list_export_item_statuses(export), else: %{}

    socket
    |> assign(:export, export)
    |> assign(:export_item_statuses, statuses)
  end

  defp has_google_token?(nil), do: false
  defp has_google_token?(scope), do: not is_nil(scope.user.google_access_token)

  defp progress_pct(0, 0), do: 0
  defp progress_pct(progress, total), do: Float.round(progress / total * 100, 1)

  defp length_or_zero(catalog) do
    case catalog do
      %{items: items} when is_list(items) -> length(items)
      _ -> 0
    end
  end

  defp item_failed?(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "failed"} -> true
      _ -> false
    end
  end

  defp item_uploaded?(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "uploaded"} -> true
      _ -> false
    end
  end

  defp item_error(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "failed", error: error} -> error
      _ -> nil
    end
  end

  defp failed_item_count(statuses) do
    Enum.count(statuses, fn {_id, %{status: s}} -> s == "failed" end)
  end
end
```

**Note on `length_or_zero/1`:** `catalog_items` is the full list in assigns. Replace the helper call with `length(@catalog_items)` in the template, or adjust the helper to take the items list. The simpler fix: in the template pass `catalog_items={@catalog_items}` to `hero_banner` and use `length(@catalog_items)`.

- [ ] **Step 2: Fix the length_or_zero helper**

In the `hero_banner` component, replace the two occurrences of `length_or_zero(@catalog)` with `length(@catalog_items)` — but first add `catalog_items` to the component's attr list by passing it from the render call:

In `render`, update the `<.hero_banner ...>` call:
```heex
      <.hero_banner
        current_scope={@current_scope}
        export={@export}
        export_progress={@export_progress}
        export_total={@export_total}
        catalog={@catalog}
        catalog_items={@catalog_items}
      />
```

Then in `hero_banner/1`, replace both `length_or_zero(@catalog)` with `length(@catalog_items)` and remove the `length_or_zero` helper.

- [ ] **Step 3: Verify it compiles and loads**

```bash
mix compile 2>&1 | grep -E "^error"
```

Expected: No errors.

- [ ] **Step 4: Start the server and manually verify the hero renders in all states**

```bash
mix phx.server
```

Open `http://localhost:4000/catalogs/<any-slug>` while:
- Logged out → should see dark slate banner with lock icon and "Log in to save"
- Logged in, no Google token → should see camera icon with "Connect Google Photos"
- Logged in with Google token, no export → should see cloud icon with "Save to Google Photos" button

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita_web/live/page/catalog_show_live.ex
git commit -m "feat: add hero banner, item error badges, and delete modal to CatalogShowLive"
```

---

## Task 8: End-to-end Manual Smoke Test

This task verifies the full flow works before wrapping up.

- [ ] **Step 1: Run the full test suite**

```bash
mix test --exclude integration 2>&1 | tail -20
```

Expected: All tests pass (Photos context tests, schema tests, existing tests).

- [ ] **Step 2: Test the export flow manually**

Start the server: `mix phx.server`

1. Log in as a user
2. Connect Google Photos (`/auth/google`)
3. Open any catalog with items
4. Verify hero shows "Not yet in your library" with blue "Save to Google Photos" button
5. Click "Save to Google Photos" — hero should switch to "Uploading…" with pulsing clock and progress bar
6. After completion — hero should show green "In your Google Photos library" with "Sync new items" and "Delete album" buttons
7. Click "Sync new items" — if no new items, progress should complete quickly
8. Click "Delete album" — confirm modal should appear
9. Confirm deletion — hero should return to "Not yet in your library" state

- [ ] **Step 3: Verify item error badges (if any items failed)**

If any items failed during export:
- Check photo grid for red borders and "⚠ FAILED" badges
- Click a failed item → lightbox should show red error banner with the error message
- Hero error state should show count of failed items

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: complete catalog hero banner and Google Photos tracking feature"
```

---

## Summary of New Files

| File | Purpose |
|------|---------|
| `priv/repo/migrations/20260323100000_create_photo_exports.exs` | photo_exports table |
| `priv/repo/migrations/20260323100001_create_photo_export_items.exs` | photo_export_items table |
| `lib/scientia_cognita/photos/photo_export.ex` | PhotoExport Ecto schema |
| `lib/scientia_cognita/photos/photo_export_item.ex` | PhotoExportItem Ecto schema |
| `lib/scientia_cognita/photos.ex` | Photos context (all DB access) |
| `lib/scientia_cognita/workers/delete_album_worker.ex` | Oban worker for album deletion |
| `test/scientia_cognita/photos_test.exs` | Photos context tests |
| `test/scientia_cognita/workers/delete_album_worker_test.exs` | Delete worker tests |

## Summary of Modified Files

| File | Change |
|------|--------|
| `config/config.exs` | Add `photoslibrary.edit.appcreateddata` OAuth scope |
| `lib/scientia_cognita/workers/export_album_worker.ex` | Rewrite: DB tracking, incremental sync, per-item errors, user-scoped PubSub |
| `lib/scientia_cognita_web/live/page/catalog_show_live.ex` | Hero banner, item error badges, delete modal, updated mount/events |
| `test/support/fixtures/catalog_fixtures.ex` | Add `catalog_fixture/1` |
