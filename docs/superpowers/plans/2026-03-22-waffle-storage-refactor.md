# Waffle Storage Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bespoke `ScientiaCognita.Storage` module with `waffle` + `waffle_ecto`, fixing the URL generation bug for Tigris (production S3) and replacing two overloaded string columns with three distinct Ecto attachment fields.

**Architecture:** A single `ItemImageUploader` (Waffle definition) stores images under `items/{id}/{filename}`. Each pipeline stage uses a named file (`original<ext>`, `processed.jpg`, `final.jpg`), stored in three separate `Waffle.Ecto.Type` fields on `Item`. Workers inject the uploader module for testability.

**Tech Stack:** Elixir/Phoenix, `waffle ~> 1.1`, `waffle_ecto ~> 0.0.12`, ExAws S3, Oban, Fsmx, Mox

**Spec:** `docs/superpowers/specs/2026-03-22-waffle-storage-refactor-design.md`

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Add | `lib/scientia_cognita/uploaders/item_image_uploader.ex` | Waffle definition — storage path, ACL, bucket, ensure_bucket_exists |
| Add | `lib/scientia_cognita/uploader_behaviour.ex` | Behaviour for store/1 and url/1, used by Mox |
| Delete | `lib/scientia_cognita/storage.ex` | Replaced by uploader |
| Delete | `lib/scientia_cognita/storage_behaviour.ex` | Replaced by uploader_behaviour |
| Modify | `mix.exs` | Add waffle + waffle_ecto deps |
| Modify | `config/config.exs` | Add `config :waffle, storage: Waffle.Storage.S3` |
| Modify | `config/test.exs` | Add waffle local storage + uploader_module mock config |
| Rewrite | `priv/repo/migrations/20260319171507_create_items.exs` | Replace storage_key/processed_key with original_image/processed_image/final_image |
| Modify | `lib/scientia_cognita/catalog/item.ex` | New field types, updated changesets, updated @type spec |
| Modify | `test/support/mocks.ex` | Replace MockStorage with MockUploader |
| Modify | `test/support/data_case.ex` | Add on_exit cleanup for priv/waffle_test |
| Modify | `test/support/fixtures/catalog_fixtures.ex` | Replace storage_key/processed_key with new fields |
| Modify | `lib/scientia_cognita/workers/download_image_worker.ex` | Use @uploader for store + store original_image |
| Modify | `test/scientia_cognita/workers/download_image_worker_test.exs` | Use MockUploader, assert original_image |
| Modify | `lib/scientia_cognita/workers/process_image_worker.ex` | Use @uploader for url + store, processed_image |
| Modify | `test/scientia_cognita/workers/process_image_worker_test.exs` | Use MockUploader, assert processed_image |
| Modify | `lib/scientia_cognita/workers/color_analysis_worker.ex` | Add @uploader, use url for processed_image |
| Modify | `test/scientia_cognita/workers/color_analysis_worker_test.exs` | Use MockUploader, fixture uses processed_image |
| Modify | `lib/scientia_cognita/workers/render_worker.ex` | Use @uploader for url + store, final_image |
| Modify | `test/scientia_cognita/workers/render_worker_test.exs` | Use MockUploader, assert final_image |
| Modify | `lib/scientia_cognita/workers/export_album_worker.ex` | Use final_image, direct url call |
| Modify | `lib/scientia_cognita/catalog.ex` | Waffle delete, final_image in get_catalog_cover_url |
| Modify | `lib/scientia_cognita/application.ex` | ensure_bucket_exists via uploader |
| Modify | `lib/scientia_cognita_web/live/console/source_show_live.ex` | Remove Storage alias, update all field refs + template |
| Modify | `test/scientia_cognita_web/live/console/source_show_live_test.exs` | Update fixture field names |
| Modify | `lib/scientia_cognita_web/live/console/sources_live.ex` | Replace Storage.get_url + field guard |
| Modify | `lib/scientia_cognita_web/live/console/catalog_show_live.ex` | Replace Storage.get_url + field guard |
| Modify | `lib/scientia_cognita_web/live/page/catalog_show_live.ex` | Replace Storage.get_url + field guard |

---

## Task 1: Add Waffle Dependencies and Create Uploader Module

**Files:**
- Modify: `mix.exs`
- Create: `lib/scientia_cognita/uploaders/item_image_uploader.ex`
- Modify: `config/config.exs`
- Modify: `config/test.exs`

- [ ] **Step 1: Add deps to mix.exs**

  In the `deps/0` function, after the `{:ex_aws_s3, "~> 2.5"},` line, add:

  ```elixir
  {:waffle, "~> 1.1"},
  {:waffle_ecto, "~> 0.0.12"},
  ```

- [ ] **Step 2: Fetch deps**

  Run: `mix deps.get`
  Expected: waffle and waffle_ecto resolved and downloaded.

- [ ] **Step 3: Create the uploader module**

  Create `lib/scientia_cognita/uploaders/item_image_uploader.ex`:

  ```elixir
  defmodule ScientiaCognita.Uploaders.ItemImageUploader do
    @moduledoc """
    Waffle uploader for item images.
    All three pipeline stages (original, processed, final) use this uploader.
    Files are stored at items/{item_id}/{filename}.
    """

    use Waffle.Definition
    use Waffle.Ecto.Definition

    @versions [:original]

    def storage_dir(_version, {_file, item}), do: "items/#{item.id}"
    def acl(_version, _), do: :public_read

    def bucket do
      Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
    end

    @doc """
    Ensures the configured S3 bucket exists, creating it if not.
    Called at application startup (moved from the deleted Storage module).
    """
    def ensure_bucket_exists do
      b = bucket()

      case ExAws.S3.head_bucket(b) |> ExAws.request() do
        {:ok, _} ->
          :ok

        {:error, {:http_error, 404, _}} ->
          b
          |> ExAws.S3.put_bucket("us-east-1")
          |> ExAws.request()
          |> case do
            {:ok, _} -> :ok
            error -> error
          end

        error ->
          error
      end
    end
  end
  ```

- [ ] **Step 4: Add Waffle S3 config to config/config.exs**

  After the `config :ex_aws, json_codec: Jason` line, add:

  ```elixir
  # T05 — Waffle file uploads (delegates to ExAws S3)
  config :waffle, storage: Waffle.Storage.S3
  ```

  Do NOT set `:waffle, :bucket` — the per-uploader `bucket/0` callback is authoritative.

- [ ] **Step 5: Add Waffle test config to config/test.exs**

  Find the `config :scientia_cognita, :storage_module, ScientiaCognita.MockStorage` line (or wherever the storage mock is configured). Add below it:

  ```elixir
  # Waffle: use local filesystem in tests (no real S3 calls)
  config :waffle, storage: Waffle.Storage.Local
  config :waffle, storage_dir_prefix: "priv/waffle_test"
  config :scientia_cognita, :uploader_module, ScientiaCognita.MockUploader
  ```

  Also remove (or update) the existing `config :scientia_cognita, :storage_module, ScientiaCognita.MockStorage` line — it will be deleted in Task 2.

- [ ] **Step 6: Verify compile**

  Run: `mix compile`
  Expected: Compiles cleanly. The old Storage module still exists and is not yet removed.

- [ ] **Step 7: Commit**

  ```bash
  git add mix.exs mix.lock lib/scientia_cognita/uploaders/ config/config.exs config/test.exs
  git commit -m "feat: add waffle deps and ItemImageUploader"
  ```

---

## Task 2: Replace StorageBehaviour with UploaderBehaviour + Update Mock

**Files:**
- Create: `lib/scientia_cognita/uploader_behaviour.ex`
- Delete: `lib/scientia_cognita/storage_behaviour.ex`
- Modify: `test/support/mocks.ex`
- Modify: `test/support/data_case.ex`

- [ ] **Step 1: Create UploaderBehaviour**

  Create `lib/scientia_cognita/uploader_behaviour.ex`:

  ```elixir
  defmodule ScientiaCognita.UploaderBehaviour do
    @moduledoc "Callback spec for the Waffle uploader — used for Mox injection in workers."

    @callback store(any()) :: {:ok, any()} | {:error, term()}
    @callback url(any()) :: String.t()
  end
  ```

- [ ] **Step 2: Update mocks.ex**

  Replace the contents of `test/support/mocks.ex`:

  ```elixir
  Mox.defmock(ScientiaCognita.MockHttp, for: ScientiaCognita.HttpBehaviour)
  Mox.defmock(ScientiaCognita.MockGemini, for: ScientiaCognita.GeminiBehaviour)
  Mox.defmock(ScientiaCognita.MockUploader, for: ScientiaCognita.UploaderBehaviour)
  ```

- [ ] **Step 3: Add cleanup to DataCase**

  In `test/support/data_case.ex`, inside the `setup tags do` block, add the waffle cleanup after the existing `setup_sandbox` call:

  ```elixir
  setup tags do
    ScientiaCognita.DataCase.setup_sandbox(tags)
    on_exit(fn -> File.rm_rf!("priv/waffle_test") end)
    :ok
  end
  ```

- [ ] **Step 4: Remove dead storage_module config from test.exs**

  In `config/test.exs`, find and remove the line:
  ```elixir
  config :scientia_cognita, :storage_module, ScientiaCognita.MockStorage
  ```
  (It was added in Task 1 Step 5 with a note to remove it here.)

- [ ] **Step 5: Delete StorageBehaviour**

  ```bash
  rm lib/scientia_cognita/storage_behaviour.ex
  ```

- [ ] **Step 6: Verify compile**

  Run: `mix compile`
  Expected: Compiles. Storage module still exists, Storage still referenced by workers and tests — that's expected at this stage.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/scientia_cognita/uploader_behaviour.ex test/support/mocks.ex test/support/data_case.ex config/test.exs
  git rm lib/scientia_cognita/storage_behaviour.ex
  git commit -m "feat: add UploaderBehaviour and MockUploader, remove StorageBehaviour"
  ```

---

## Task 3: Rewrite Migration and Update Item Schema

**Files:**
- Rewrite: `priv/repo/migrations/20260319171507_create_items.exs`
- Modify: `lib/scientia_cognita/catalog/item.ex`

- [ ] **Step 1: Rewrite the items migration**

  Replace the entire contents of `priv/repo/migrations/20260319171507_create_items.exs`:

  ```elixir
  defmodule ScientiaCognita.Repo.Migrations.CreateItems do
    use Ecto.Migration

    def change do
      create table(:items) do
        add :title, :string, null: false
        add :description, :text
        add :author, :string
        add :copyright, :string
        add :original_url, :string
        add :original_image,  :string
        add :processed_image, :string
        add :final_image,     :string
        add :status, :string, null: false, default: "pending"
        add :error, :text
        add :source_id, references(:sources, on_delete: :delete_all), null: false

        timestamps(type: :utc_datetime)
      end

      create index(:items, [:source_id])
      create index(:items, [:status])
    end
  end
  ```

- [ ] **Step 2: Update Item schema fields**

  In `lib/scientia_cognita/catalog/item.ex`:

  a) Add the alias at the top of the module (after `use Fsmx.Struct`):
  ```elixir
  alias ScientiaCognita.Uploaders.ItemImageUploader
  ```

  b) Update `@type t` — replace:
  ```elixir
  storage_key: String.t() | nil,
  processed_key: String.t() | nil,
  ```
  With:
  ```elixir
  original_image:  term() | nil,
  processed_image: term() | nil,
  final_image:     term() | nil,
  ```
  (Use `term()` rather than `String.t()` — these are `Waffle.Ecto.Type` fields whose runtime value is an opaque struct or string, not a plain `String.t()`.)

  c) In the `schema "items"` block, replace:
  ```elixir
  field :storage_key, :string
  field :processed_key, :string
  ```
  With:
  ```elixir
  field :original_image,  ItemImageUploader.Type
  field :processed_image, ItemImageUploader.Type
  field :final_image,     ItemImageUploader.Type
  ```

- [ ] **Step 3: Update FSM transition changesets in item.ex**

  a) `downloading → processing` — replace `:storage_key` with `:original_image`:
  ```elixir
  def transition_changeset(changeset, "downloading", "processing", params) do
    changeset
    |> cast(params, [:original_image])
    |> validate_required([:original_image])
    |> put_change(:error, nil)
  end
  ```

  b) `processing → color_analysis` — replace `:processed_key` with `:processed_image`:
  ```elixir
  def transition_changeset(changeset, "processing", "color_analysis", params) do
    changeset
    |> cast(params, [:processed_image])
    |> validate_required([:processed_image])
  end
  ```

  c) `render → ready` — replace `:processed_key` with `:final_image`:
  ```elixir
  def transition_changeset(changeset, "render", "ready", params) do
    changeset
    |> cast(params, [:final_image])
    |> put_change(:error, nil)
  end
  ```

  Also update the module doc comment above this transition to remove the note about "eliminating a separate update_item_storage call" which no longer applies.

- [ ] **Step 4: Update storage_changeset/2**

  Replace:
  ```elixir
  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:storage_key, :processed_key])
  end
  ```
  With:
  ```elixir
  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:original_image, :processed_image, :final_image])
  end
  ```

- [ ] **Step 5: Run item schema tests — expect some failures**

  Run: `mix test test/scientia_cognita/catalog/item_test.exs`
  The tests that reference `storage_key` or `processed_key` field names will fail. Tests that only check status transitions should still pass. This confirms the new schema is active — failures here are expected and will be fixed when fixtures are updated in Task 4.

- [ ] **Step 6: Commit**

  ```bash
  git add priv/repo/migrations/20260319171507_create_items.exs lib/scientia_cognita/catalog/item.ex
  git commit -m "feat: replace storage_key/processed_key with waffle attachment fields"
  ```

---

## Task 4: Update Catalog Fixtures and Catalog Context

**Files:**
- Modify: `test/support/fixtures/catalog_fixtures.ex`
- Modify: `lib/scientia_cognita/catalog.ex`

- [ ] **Step 1: Update item_fixture/2 in catalog_fixtures.ex**

  > **Important:** `Waffle.Ecto.Type.cast/1` behaviour with plain strings varies by version. To guarantee fixtures always work, set image fields via `Ecto.Changeset.change/2` (which bypasses `cast` entirely and writes directly to the DB as a string). `Waffle.Ecto.Type.load/1` will convert the string back to the expected struct on read.

  Replace the `{storage_key, attrs}` / `{processed_key, attrs}` pop section with new fields:

  ```elixir
  def item_fixture(source, attrs \\ %{}) do
    {status, attrs}          = Map.pop(attrs, :status, "pending")
    {original_image, attrs}  = Map.pop(attrs, :original_image)
    {processed_image, attrs} = Map.pop(attrs, :processed_image)
    {final_image, attrs}     = Map.pop(attrs, :final_image)
    {text_color, attrs}      = Map.pop(attrs, :text_color)
    {bg_color, attrs}        = Map.pop(attrs, :bg_color)
    {bg_opacity, attrs}      = Map.pop(attrs, :bg_opacity)

    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image-#{System.unique_integer([:positive])}.jpg",
        source_id: source.id
      })
      |> Catalog.create_item()

    # Use Ecto.Changeset.change/2 (not cast) to set image fields with plain
    # string filenames — bypasses Waffle.Ecto.Type.cast/1, which is correct for
    # test setup where we're simulating an already-stored file, not uploading one.
    item =
      if original_image || processed_image || final_image do
        changes =
          %{}
          |> then(fn a -> if original_image,  do: Map.put(a, :original_image,  original_image),  else: a end)
          |> then(fn a -> if processed_image, do: Map.put(a, :processed_image, processed_image), else: a end)
          |> then(fn a -> if final_image,     do: Map.put(a, :final_image,     final_image),     else: a end)

        {:ok, item} =
          item
          |> Ecto.Changeset.change(changes)
          |> ScientiaCognita.Repo.update()

        item
      else
        item
      end

    item =
      if text_color && bg_color && bg_opacity do
        {:ok, item} =
          ScientiaCognita.Catalog.update_item_colors(item, %{
            text_color: text_color,
            bg_color: bg_color,
            bg_opacity: bg_opacity
          })
        item
      else
        item
      end

    if status != "pending" do
      {:ok, item} = ScientiaCognita.Catalog.update_item_status(item, status)
      item
    else
      item
    end
  end
  ```

- [ ] **Step 2: Update delete_source_with_storage/1 in catalog.ex**

  Replace the `Enum.each` block that calls `Storage.delete/1`:

  ```elixir
  def delete_source_with_storage(%Source{} = source) do
    items = list_items_by_source(source)

    Enum.each(items, fn item ->
      if item.original_image,  do: ScientiaCognita.Uploaders.ItemImageUploader.delete({item.original_image,  item})
      if item.processed_image, do: ScientiaCognita.Uploaders.ItemImageUploader.delete({item.processed_image, item})
      if item.final_image,     do: ScientiaCognita.Uploaders.ItemImageUploader.delete({item.final_image,     item})
    end)

    Repo.delete(source)
  end
  ```

- [ ] **Step 3: Update get_catalog_cover_url/1 in catalog.ex**

  Replace the function:

  ```elixir
  def get_catalog_cover_url(%Catalog{id: catalog_id}) do
    item =
      Repo.one(
        from i in Item,
          join: ci in CatalogItem,
          on: ci.item_id == i.id,
          where: ci.catalog_id == ^catalog_id and not is_nil(i.final_image),
          order_by: [asc: ci.position, asc: ci.inserted_at],
          limit: 1
      )

    if item, do: ScientiaCognita.Uploaders.ItemImageUploader.url({item.final_image, item}), else: nil
  end
  ```

  Also remove the `alias ScientiaCognita.Storage` (or any `Storage` references) from `catalog.ex`.

- [ ] **Step 4: Compile check**

  Run: `mix compile`
  Expected: Compiles. Worker and LiveView files still reference old fields/Storage module — compile-time errors not yet expected since Elixir doesn't validate field names.

- [ ] **Step 5: Commit**

  ```bash
  git add test/support/fixtures/catalog_fixtures.ex lib/scientia_cognita/catalog.ex
  git commit -m "feat: update fixtures and catalog context for waffle fields"
  ```

---

## Task 5: Update DownloadImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/download_image_worker.ex`
- Modify: `test/scientia_cognita/workers/download_image_worker_test.exs`

- [ ] **Step 1: Update the test first**

  Replace `test/scientia_cognita/workers/download_image_worker_test.exs`:

  ```elixir
  defmodule ScientiaCognita.Workers.DownloadImageWorkerTest do
    use ScientiaCognita.DataCase
    use Oban.Testing, repo: ScientiaCognita.Repo

    import Mox
    import ScientiaCognita.CatalogFixtures

    alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
    alias ScientiaCognita.Workers.{DownloadImageWorker, ProcessImageWorker}

    setup :verify_on_exit!

    describe "perform/1 — happy path" do
      test "downloads image, uploads via uploader, transitions to processing, enqueues ProcessImageWorker" do
        source = source_fixture()
        item = item_fixture(source, %{original_url: "https://example.com/image.jpg"})

        expect(MockHttp, :get, fn _url, _opts ->
          {:ok,
           %{status: 200, body: <<255, 216, 255>>, headers: %{"content-type" => ["image/jpeg"]}}}
        end)

        expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "original.jpg"} end)

        assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "processing"
        assert item.original_image != nil

        assert_enqueued(worker: ProcessImageWorker, args: %{"item_id" => item.id})
      end
    end

    describe "perform/1 — HTTP error" do
      test "marks item as failed on download error" do
        source = source_fixture()
        item = item_fixture(source, %{original_url: "https://example.com/image.jpg"})

        expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

        assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "failed"
      end
    end
  end
  ```

- [ ] **Step 2: Run the test — expect failure**

  Run: `mix test test/scientia_cognita/workers/download_image_worker_test.exs`
  Expected: Fails — worker still uses `MockStorage` and `storage_key`.

- [ ] **Step 3: Update DownloadImageWorker**

  Replace `lib/scientia_cognita/workers/download_image_worker.ex`:

  ```elixir
  defmodule ScientiaCognita.Workers.DownloadImageWorker do
    @moduledoc """
    Downloads an item's original image from its source URL and uploads it to S3.
    On success, enqueues ProcessImageWorker.

    Args: %{item_id: integer}
    """

    use Oban.Worker, queue: :fetch, max_attempts: 3

    require Logger

    alias ScientiaCognita.{Catalog, Repo}
    alias ScientiaCognita.Workers.ProcessImageWorker

    @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
    @uploader Application.compile_env(:scientia_cognita, :uploader_module,
                ScientiaCognita.Uploaders.ItemImageUploader)

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
      item = Catalog.get_item!(item_id)

      unless item.original_url do
        Logger.warning("[DownloadImageWorker] item=#{item_id} has no original_url, skipping")
        :ok
      else
        Logger.info("[DownloadImageWorker] item=#{item_id} url=#{item.original_url}")

        with {:ok, item} <- fsm_transition(item, "downloading"),
             {:ok, {binary, content_type}} <- download(item.original_url),
             ext = ext_from_content_type(content_type),
             {:ok, file} <- @uploader.store({%{binary: binary, file_name: "original#{ext}"}, item}),
             {:ok, item} <- fsm_transition(item, "processing", %{original_image: file}) do
          broadcast(item.source_id, {:item_updated, item})
          %{item_id: item_id} |> ProcessImageWorker.new() |> Oban.insert()
          :ok
        else
          {:error, :invalid_transition} ->
            Logger.warning("[DownloadImageWorker] invalid transition for item=#{item_id}")
            :ok

          {:error, reason} ->
            Logger.error("[DownloadImageWorker] failed item=#{item_id}: #{inspect(reason)}")
            item = Catalog.get_item!(item_id)
            {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
            broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
            :ok
        end
      end
    end

    defp download(url) do
      case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: body, headers: headers}} ->
          content_type =
            case Map.get(headers, "content-type") do
              [ct | _] -> ct |> String.split(";") |> hd() |> String.trim()
              nil -> "image/jpeg"
            end

          {:ok, {body, content_type}}

        {:ok, %{status: status}} ->
          {:error, "HTTP #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp ext_from_content_type("image/jpeg"), do: ".jpg"
    defp ext_from_content_type("image/png"), do: ".png"
    defp ext_from_content_type("image/webp"), do: ".webp"
    defp ext_from_content_type("image/gif"), do: ".gif"
    defp ext_from_content_type(_), do: ".jpg"

    defp broadcast(source_id, event) do
      Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
    end

    defp fsm_transition(schema, new_state, params \\ %{}) do
      Ecto.Multi.new()
      |> Fsmx.transition_multi(schema, :transition, new_state, params, state_field: :status)
      |> Repo.transaction()
      |> case do
        {:ok, %{transition: updated}} ->
          {:ok, updated}

        {:error, :transition, %Ecto.Changeset{} = cs, _} ->
          if Keyword.has_key?(cs.errors, :status) do
            {:error, :invalid_transition}
          else
            {:error, cs}
          end

        {:error, _, reason, _} ->
          {:error, reason}
      end
    end
  end
  ```

- [ ] **Step 4: Run the test — expect pass**

  Run: `mix test test/scientia_cognita/workers/download_image_worker_test.exs`
  Expected: Both tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/scientia_cognita/workers/download_image_worker.ex \
          test/scientia_cognita/workers/download_image_worker_test.exs
  git commit -m "feat: migrate DownloadImageWorker to waffle uploader"
  ```

---

## Task 6: Update ProcessImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/process_image_worker.ex`
- Modify: `test/scientia_cognita/workers/process_image_worker_test.exs`

- [ ] **Step 1: Update the test first**

  Replace `test/scientia_cognita/workers/process_image_worker_test.exs`:

  ```elixir
  defmodule ScientiaCognita.Workers.ProcessImageWorkerTest do
    use ScientiaCognita.DataCase
    use Oban.Testing, repo: ScientiaCognita.Repo

    import Mox
    import ScientiaCognita.CatalogFixtures

    alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
    alias ScientiaCognita.Workers.{ProcessImageWorker, ColorAnalysisWorker}

    setup :verify_on_exit!

    describe "perform/1 — happy path" do
      test "downloads original, resizes to 1920x1080, uploads processed, transitions to color_analysis" do
        source = source_fixture()
        item = item_fixture(source, %{status: "processing", original_image: "original.jpg"})

        # Mock: url for fetching original from S3
        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/original.jpg" end)

        # Mock: download original
        expect(MockHttp, :get, fn _url, _opts ->
          jpeg = File.read!("test/fixtures/test_image.jpg")
          {:ok, %{status: 200, body: jpeg, headers: %{}}}
        end)

        # Mock: upload processed image
        expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "processed.jpg"} end)

        assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "color_analysis"
        assert item.processed_image != nil

        assert_enqueued(worker: ColorAnalysisWorker, args: %{"item_id" => item.id})
      end
    end

    describe "perform/1 — HTTP error" do
      test "marks item as failed when original image download fails" do
        source = source_fixture()
        item = item_fixture(source, %{status: "processing", original_image: "original.jpg"})

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/original.jpg" end)
        expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

        assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "failed"
        assert item.error =~ "timeout"
      end
    end
  end
  ```

- [ ] **Step 2: Run the test — expect failure**

  Run: `mix test test/scientia_cognita/workers/process_image_worker_test.exs`
  Expected: Fails — worker still uses Storage and old field names.

- [ ] **Step 3: Update ProcessImageWorker**

  Replace `lib/scientia_cognita/workers/process_image_worker.ex`:

  ```elixir
  defmodule ScientiaCognita.Workers.ProcessImageWorker do
    @moduledoc """
    Downloads an item's original image from S3, resizes and crops it to
    1920×1080 (16:9 FHD), and uploads the processed variant.
    On success, enqueues ColorAnalysisWorker.

    Args: %{item_id: integer}
    """

    use Oban.Worker, queue: :process, max_attempts: 3

    require Logger

    alias ScientiaCognita.{Catalog, Repo}
    alias ScientiaCognita.Workers.ColorAnalysisWorker

    @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
    @uploader Application.compile_env(:scientia_cognita, :uploader_module,
                ScientiaCognita.Uploaders.ItemImageUploader)

    @target_width 1920
    @target_height 1080

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
      item = Catalog.get_item!(item_id)
      Logger.info("[ProcessImageWorker] item=#{item_id}")

      with {:ok, original_binary} <- download_original(item),
           {:ok, img} <- Image.from_binary(original_binary),
           {:ok, resized} <-
             Image.thumbnail(img, @target_width, height: @target_height, crop: :center),
           {:ok, output_binary} <- Image.write(resized, :memory, suffix: ".jpg", quality: 85),
           {:ok, file} <- @uploader.store({%{binary: output_binary, file_name: "processed.jpg"}, item}),
           {:ok, item} <- fsm_transition(item, "color_analysis", %{processed_image: file}) do
        broadcast(item.source_id, {:item_updated, item})
        %{item_id: item_id} |> ColorAnalysisWorker.new() |> Oban.insert()
        :ok
      else
        {:error, :invalid_transition} ->
          Logger.warning("[ProcessImageWorker] invalid transition for item=#{item_id}")
          :ok

        {:error, reason} ->
          Logger.error("[ProcessImageWorker] failed item=#{item_id}: #{inspect(reason)}")
          item = Catalog.get_item!(item_id)
          {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
          broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
          :ok
      end
    end

    defp download_original(%{original_image: nil}), do: {:error, "item has no original_image"}

    defp download_original(item) do
      url = @uploader.url({item.original_image, item})

      case @http.get(url, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
        {:error, reason} -> {:error, reason}
      end
    end

    defp fsm_transition(schema, new_state, params) do
      Ecto.Multi.new()
      |> Fsmx.transition_multi(schema, :transition, new_state, params, state_field: :status)
      |> Repo.transaction()
      |> case do
        {:ok, %{transition: updated}} ->
          {:ok, updated}

        {:error, :transition, %Ecto.Changeset{} = cs, _} ->
          if Keyword.has_key?(cs.errors, :status) do
            {:error, :invalid_transition}
          else
            {:error, cs}
          end

        {:error, _, reason, _} ->
          {:error, reason}
      end
    end

    defp broadcast(source_id, event) do
      Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
    end
  end
  ```

- [ ] **Step 4: Run the test — expect pass**

  Run: `mix test test/scientia_cognita/workers/process_image_worker_test.exs`
  Expected: Both tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/scientia_cognita/workers/process_image_worker.ex \
          test/scientia_cognita/workers/process_image_worker_test.exs
  git commit -m "feat: migrate ProcessImageWorker to waffle uploader"
  ```

---

## Task 7: Update ColorAnalysisWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/color_analysis_worker.ex`
- Modify: `test/scientia_cognita/workers/color_analysis_worker_test.exs`

- [ ] **Step 1: Update the test first**

  Replace `test/scientia_cognita/workers/color_analysis_worker_test.exs`:

  ```elixir
  defmodule ScientiaCognita.Workers.ColorAnalysisWorkerTest do
    use ScientiaCognita.DataCase
    use Oban.Testing, repo: ScientiaCognita.Repo

    import Mox
    import ScientiaCognita.CatalogFixtures

    alias ScientiaCognita.{Catalog, MockHttp, MockGemini, MockUploader}
    alias ScientiaCognita.Workers.{ColorAnalysisWorker, RenderWorker}

    setup :verify_on_exit!

    @color_response %{
      "text_color" => "#FFFFFF",
      "bg_color" => "#1A1A2E",
      "bg_opacity" => 0.75
    }

    describe "perform/1 — happy path" do
      test "downloads processed image, calls Gemini for colors, stores colors, enqueues RenderWorker" do
        source = source_fixture()

        item =
          item_fixture(source, %{
            status: "color_analysis",
            processed_image: "processed.jpg"
          })

        jpeg = File.read!("test/fixtures/test_image.jpg")

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/processed.jpg" end)

        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: jpeg, headers: %{}}}
        end)

        expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
          {:ok, @color_response}
        end)

        assert :ok = perform_job(ColorAnalysisWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "render"
        assert item.text_color == "#FFFFFF"
        assert item.bg_color == "#1A1A2E"
        assert item.bg_opacity == 0.75

        assert_enqueued(worker: RenderWorker, args: %{"item_id" => item.id})
      end
    end

    describe "perform/1 — Gemini error" do
      test "falls back to default colors and continues" do
        source = source_fixture()

        item =
          item_fixture(source, %{
            status: "color_analysis",
            processed_image: "processed.jpg"
          })

        jpeg = File.read!("test/fixtures/test_image.jpg")

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/processed.jpg" end)

        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: jpeg, headers: %{}}}
        end)

        expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
          {:error, "API quota exceeded"}
        end)

        assert :ok = perform_job(ColorAnalysisWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "render"
        assert item.text_color == "#FFFFFF"
        assert item.bg_color == "#000000"
      end
    end
  end
  ```

- [ ] **Step 2: Run the test — expect failure**

  Run: `mix test test/scientia_cognita/workers/color_analysis_worker_test.exs`
  Expected: Fails.

- [ ] **Step 3: Update ColorAnalysisWorker**

  In `lib/scientia_cognita/workers/color_analysis_worker.ex`:

  a) Remove `alias ScientiaCognita.{Catalog, Repo, Storage}` and replace with:
  ```elixir
  alias ScientiaCognita.{Catalog, Repo}
  ```

  b) Add the `@uploader` compile-env attribute after `@gemini`:
  ```elixir
  @uploader Application.compile_env(:scientia_cognita, :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader)
  ```

  c) In `perform/1`, change `download_processed(item.processed_key)` to:
  ```elixir
  download_processed(item)
  ```

  d) Replace `download_processed/1` private function:
  ```elixir
  defp download_processed(%{processed_image: nil}), do: {:error, "item has no processed_image"}

  defp download_processed(item) do
    url = @uploader.url({item.processed_image, item})

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
  ```

- [ ] **Step 4: Run the test — expect pass**

  Run: `mix test test/scientia_cognita/workers/color_analysis_worker_test.exs`
  Expected: Both tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/scientia_cognita/workers/color_analysis_worker.ex \
          test/scientia_cognita/workers/color_analysis_worker_test.exs
  git commit -m "feat: migrate ColorAnalysisWorker to waffle uploader"
  ```

---

## Task 8: Update RenderWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/render_worker.ex`
- Modify: `test/scientia_cognita/workers/render_worker_test.exs`

- [ ] **Step 1: Update the test first**

  Replace `test/scientia_cognita/workers/render_worker_test.exs`:

  ```elixir
  defmodule ScientiaCognita.Workers.RenderWorkerTest do
    use ScientiaCognita.DataCase
    use Oban.Testing, repo: ScientiaCognita.Repo

    import Mox
    import ScientiaCognita.CatalogFixtures

    alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
    alias ScientiaCognita.Workers.RenderWorker

    setup :verify_on_exit!

    describe "perform/1 — happy path" do
      test "downloads processed image, renders text overlay, uploads final, marks ready" do
        source = source_fixture()

        item =
          item_fixture(source, %{
            status: "render",
            title: "Orion Nebula",
            description: "A stellar nursery",
            processed_image: "processed.jpg",
            text_color: "#FFFFFF",
            bg_color: "#1A1A2E",
            bg_opacity: 0.75
          })

        jpeg = File.read!("test/fixtures/test_image.jpg")

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/processed.jpg" end)

        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: jpeg, headers: %{}}}
        end)

        expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

        assert :ok = perform_job(RenderWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "ready"
        assert item.final_image != nil
      end
    end

    describe "perform/1 — uses default colors when item has no colors stored" do
      test "renders with fallback colors if text_color is nil" do
        source = source_fixture()

        item =
          item_fixture(source, %{
            status: "render",
            processed_image: "processed.jpg"
            # text_color, bg_color, bg_opacity are nil
          })

        jpeg = File.read!("test/fixtures/test_image.jpg")

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/processed.jpg" end)
        expect(MockHttp, :get, fn _url, _opts -> {:ok, %{status: 200, body: jpeg, headers: %{}}} end)
        expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

        assert :ok = perform_job(RenderWorker, %{item_id: item.id})

        item = Catalog.get_item!(item.id)
        assert item.status == "ready"
      end
    end

    describe "perform/1 — source completion" do
      test "transitions source to done when last item finishes" do
        source = source_fixture(%{status: "items_loading"})

        item =
          item_fixture(source, %{
            status: "render",
            processed_image: "processed.jpg",
            text_color: "#FFFFFF",
            bg_color: "#000000",
            bg_opacity: 0.75
          })

        jpeg = File.read!("test/fixtures/test_image.jpg")

        expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/processed.jpg" end)
        expect(MockHttp, :get, fn _url, _opts -> {:ok, %{status: 200, body: jpeg, headers: %{}}} end)
        expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

        assert :ok = perform_job(RenderWorker, %{item_id: item.id})

        source = Catalog.get_source!(source.id)
        assert source.status == "done"
      end
    end
  end
  ```

- [ ] **Step 2: Run the test — expect failure**

  Run: `mix test test/scientia_cognita/workers/render_worker_test.exs`
  Expected: Fails.

- [ ] **Step 3: Update RenderWorker**

  In `lib/scientia_cognita/workers/render_worker.ex`:

  a) Remove `alias ScientiaCognita.{Catalog, Repo, Storage}` → replace with `alias ScientiaCognita.{Catalog, Repo}`.

  b) Add `@uploader` after `@http`:
  ```elixir
  @uploader Application.compile_env(:scientia_cognita, :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader)
  ```

  c) In `perform/1`, update the `with` chain:
  - Change `download_processed(item.processed_key)` → `download_processed(item)`
  - Change `final_key = Storage.item_key(item.id, :final, ".jpg")` → remove this line
  - Change `@storage.upload(final_key, output_binary, content_type: "image/jpeg")` →
    `@uploader.store({%{binary: output_binary, file_name: "final.jpg"}, item})`
  - Bind result as `file` not `_`:
    `{:ok, file} <- @uploader.store(...)`
  - Change FSM transition params `%{processed_key: final_key}` → `%{final_image: file}`

  d) Replace `download_processed/1`:
  ```elixir
  defp download_processed(%{processed_image: nil}), do: {:error, "item has no processed_image"}

  defp download_processed(item) do
    case @http.get(@uploader.url({item.processed_image, item}), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
  ```

- [ ] **Step 4: Run the test — expect pass**

  Run: `mix test test/scientia_cognita/workers/render_worker_test.exs`
  Expected: All three tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/scientia_cognita/workers/render_worker.ex \
          test/scientia_cognita/workers/render_worker_test.exs
  git commit -m "feat: migrate RenderWorker to waffle uploader, store final_image"
  ```

---

## Task 9: Update ExportAlbumWorker and application.ex

**Files:**
- Modify: `lib/scientia_cognita/workers/export_album_worker.ex`
- Modify: `lib/scientia_cognita/application.ex`

- [ ] **Step 1: Update ExportAlbumWorker**

  In `lib/scientia_cognita/workers/export_album_worker.ex`:

  a) Remove `alias ScientiaCognita.{Catalog, Accounts, Storage}` → replace with:
  ```elixir
  alias ScientiaCognita.{Catalog, Accounts}
  alias ScientiaCognita.Uploaders.ItemImageUploader
  ```

  b) In `perform/1`, change:
  ```elixir
  total = Enum.count(items, & &1.processed_key)
  ```
  To:
  ```elixir
  total = Enum.count(items, & &1.final_image)
  ```

  c) Change:
  ```elixir
  |> Enum.filter(& &1.processed_key)
  ```
  To:
  ```elixir
  |> Enum.filter(& &1.final_image)
  ```

  d) Change:
  ```elixir
  image_binary = fetch_image(item.processed_key)
  ```
  To:
  ```elixir
  image_binary = fetch_image(item)
  ```

  e) Replace `fetch_image/1`:
  ```elixir
  # Intentional: uses Req.get! directly rather than @http injection.
  # ExportAlbumWorker is not unit-tested with a storage mock; direct call is fine here.
  defp fetch_image(item) do
    url = ItemImageUploader.url({item.final_image, item})
    response = Req.get!(url)
    response.body
  end
  ```

- [ ] **Step 2: Update application.ex**

  In `lib/scientia_cognita/application.ex`, replace:
  ```elixir
  Task.start(fn -> ScientiaCognita.Storage.ensure_bucket_exists() end)
  ```
  With:
  ```elixir
  Task.start(fn -> ScientiaCognita.Uploaders.ItemImageUploader.ensure_bucket_exists() end)
  ```

- [ ] **Step 3: Compile check**

  Run: `mix compile`
  Expected: Compiles cleanly. `Storage` module is still referenced by LiveViews — that's expected.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/scientia_cognita/workers/export_album_worker.ex \
          lib/scientia_cognita/application.ex
  git commit -m "feat: migrate ExportAlbumWorker and application startup to waffle"
  ```

---

## Task 10: Update SourceShowLive + Test

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`
- Modify: `test/scientia_cognita_web/live/console/source_show_live_test.exs`

- [ ] **Step 1: Update source_show_live_test.exs**

  In `test/scientia_cognita_web/live/console/source_show_live_test.exs`, replace all occurrences of:
  - `storage_key: "sk"` → `original_image: "original.jpg"`
  - `storage_key: "images/original.jpg"` → `original_image: "original.jpg"`
  - `processed_key: "pk"` → `final_image: "final.jpg"`
  - `processed_key: "images/processed.jpg"` → `processed_image: "processed.jpg"`
  - `processed_key: "images/final.jpg"` → `final_image: "final.jpg"`

  Also update the assertions that check field values:
  - `assert reloaded.storage_key == "images/original.jpg"` → `assert not is_nil(reloaded.original_image)` (Waffle.Ecto.Type fields hold a struct/string after load — do not assert the exact string)
  - `assert is_nil(reloaded.processed_key)` → `assert is_nil(reloaded.processed_image) and is_nil(reloaded.final_image)`
  - The `updated = %{item | status: "ready", processed_key: "images/done.jpg"}` struct update in the PubSub test → `updated = %{item | status: "ready", final_image: "done.jpg"}`

  Also update the comment: `# No storage_key set (default nil)` → `# No original_image set (default nil)`
  And: `# Item status reset to "processing", processed_key and color fields cleared` → `# Item status reset to "processing", processed_image/final_image and color fields cleared`

- [ ] **Step 2: Run the test — expect failure**

  Run: `mix test test/scientia_cognita_web/live/console/source_show_live_test.exs`
  Expected: Fails (LiveView still uses old field names and Storage alias).

- [ ] **Step 3: Update source_show_live.ex — aliases and imports**

  Replace the two alias lines at the top:
  ```elixir
  alias ScientiaCognita.{Catalog, Storage}
  ```
  With:
  ```elixir
  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Uploaders.ItemImageUploader
  ```

- [ ] **Step 4: Update source_show_live.ex — template Storage.get_url calls**

  In the `render/1` template, replace all `Storage.get_url(...)` calls:

  a) The modal image for "render" status (line ~184):
  ```heex
  src={ItemImageUploader.url({@selected_item.processed_image || @selected_item.original_image, @selected_item})}
  ```

  b) The modal image fallback (line ~190):
  ```heex
  src={ItemImageUploader.url({@selected_item.processed_image || @selected_item.original_image, @selected_item})}
  ```

  c) Update the `:if` guards for the modal image (lines ~183, ~188):
  ```heex
  :if={@selected_item.processed_image || @selected_item.original_image}
  ```
  and:
  ```heex
  <% @selected_item.processed_image || @selected_item.original_image -> %>
  ```

  d) The Re-render button `:if` guard (line ~245):
  ```heex
  :if={(@selected_item.status in ~w(ready failed) or not is_nil(@selected_item.error)) and not is_nil(@selected_item.original_image)}
  ```

  e) In `item_thumbnail/1` component, the `:render` branch:
  ```heex
  src={ItemImageUploader.url({@item.processed_image, @item})}
  ```

  f) In `item_thumbnail/1`, the `:image` branch — change to use `thumb_url(@item)` directly (not wrapped in Storage.get_url — `thumb_url/1` will return the URL itself):
  ```heex
  src={thumb_url(@item)}
  ```

- [ ] **Step 5: Update source_show_live.ex — redownload_item handler**

  Replace the `update_item_storage` call in `handle_event("redownload_item", ...)`:
  ```elixir
  {:ok, item} = Catalog.update_item_storage(item, %{original_image: nil, processed_image: nil, final_image: nil})
  ```

- [ ] **Step 6: Update source_show_live.ex — rerender_item handler**

  Replace the `Ecto.Changeset.change` call in `handle_event("rerender_item", ...)`.
  Remove `processed_key: nil` and substitute with new fields (retain `original_image`):
  ```elixir
  {:ok, item} =
    item
    |> Ecto.Changeset.change(%{
      processed_image: nil,
      final_image: nil,
      text_color: nil,
      bg_color: nil,
      bg_opacity: nil
    })
    |> ScientiaCognita.Repo.update()
  ```
  Also update the inline comment above to remove the `processed_key` reference.

- [ ] **Step 7: Update source_show_live.ex — retry routing**

  In `handle_event("retry_failed_items", ...)`, replace:
  ```elixir
  is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
  is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
  ```
  With:
  ```elixir
  is_nil(item.original_image) -> {"pending", DownloadImageWorker}
  is_nil(item.processed_image) -> {"processing", ProcessImageWorker}
  ```

- [ ] **Step 8: Update source_show_live.ex — thumb_type/1 and thumb_url/1**

  Replace `thumb_type/1`:
  ```elixir
  defp thumb_type(%{status: s}) when s in ~w(pending downloading), do: :shimmer
  defp thumb_type(%{status: "failed", original_image: nil}), do: :icon
  defp thumb_type(%{status: "failed"}), do: :image
  defp thumb_type(%{status: "render"}), do: :render
  defp thumb_type(%{final_image: fi}) when not is_nil(fi), do: :image
  defp thumb_type(%{processed_image: pi}) when not is_nil(pi), do: :image
  defp thumb_type(%{original_image: oi}) when not is_nil(oi), do: :image
  defp thumb_type(_), do: :shimmer
  ```

  Replace `thumb_url/1` — now returns the URL string directly:
  ```elixir
  defp thumb_url(%{status: "failed", final_image: fi} = item) when not is_nil(fi),
    do: ItemImageUploader.url({fi, item})
  defp thumb_url(%{status: "failed", processed_image: pi} = item) when not is_nil(pi),
    do: ItemImageUploader.url({pi, item})
  defp thumb_url(%{status: "failed", original_image: oi} = item) when not is_nil(oi),
    do: ItemImageUploader.url({oi, item})
  defp thumb_url(%{final_image: fi} = item) when not is_nil(fi),
    do: ItemImageUploader.url({fi, item})
  defp thumb_url(%{processed_image: pi} = item) when not is_nil(pi),
    do: ItemImageUploader.url({pi, item})
  defp thumb_url(%{original_image: oi} = item) when not is_nil(oi),
    do: ItemImageUploader.url({oi, item})
  defp thumb_url(_), do: nil
  ```

  Update the comment above `thumb_type/1` to reference new field names.

- [ ] **Step 9: Run the test — expect pass**

  Run: `mix test test/scientia_cognita_web/live/console/source_show_live_test.exs`
  Expected: All tests pass.

- [ ] **Step 10: Commit**

  ```bash
  git add lib/scientia_cognita_web/live/console/source_show_live.ex \
          test/scientia_cognita_web/live/console/source_show_live_test.exs
  git commit -m "feat: migrate SourceShowLive to waffle uploader fields"
  ```

---

## Task 11: Update Remaining LiveViews

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`
- Modify: `lib/scientia_cognita_web/live/page/catalog_show_live.ex`

These three files all follow the same pattern: replace `Storage.get_url(item.processed_key)` with `ItemImageUploader.url({item.final_image, item})` and `:if={item.processed_key}` with `:if={item.final_image}`.

- [ ] **Step 1: Update sources_live.ex**

  a) Remove `alias ScientiaCognita.Storage` (or update the alias line).
  b) Add: `alias ScientiaCognita.Uploaders.ItemImageUploader`
  c) In template, replace:
  ```heex
  :if={item.processed_key}
  src={ScientiaCognita.Storage.get_url(item.processed_key)}
  ```
  With:
  ```heex
  :if={item.final_image}
  src={ItemImageUploader.url({item.final_image, item})}
  ```

- [ ] **Step 2: Update console/catalog_show_live.ex**

  a) Remove `alias ... Storage` from the alias block.
  b) Add: `alias ScientiaCognita.Uploaders.ItemImageUploader`
  c) In the template, replace both occurrences of:
  ```heex
  :if={item.processed_key}
  src={Storage.get_url(item.processed_key)}
  ```
  With:
  ```heex
  :if={item.final_image}
  src={ItemImageUploader.url({item.final_image, item})}
  ```

- [ ] **Step 3: Update page/catalog_show_live.ex**

  a) Remove `alias ... Storage`.
  b) Add: `alias ScientiaCognita.Uploaders.ItemImageUploader`
  c) Replace all three occurrences of `Storage.get_url(item.processed_key)` / `Storage.get_url(@lightbox_item.processed_key)`:
  - `src={Storage.get_url(item.processed_key)}` → `src={ItemImageUploader.url({item.final_image, item})}`
  - `:if={item.processed_key}` → `:if={item.final_image}`
  - `src={Storage.get_url(@lightbox_item.processed_key)}` → `src={ItemImageUploader.url({@lightbox_item.final_image, @lightbox_item})}`
  - `:if={@lightbox_item.processed_key}` → `:if={@lightbox_item.final_image}`

- [ ] **Step 4: Compile check**

  Run: `mix compile`
  Expected: Compiles cleanly. Only `Storage` module itself should still be left in `lib/scientia_cognita/storage.ex` — it is no longer referenced.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/scientia_cognita_web/live/console/sources_live.ex \
          lib/scientia_cognita_web/live/console/catalog_show_live.ex \
          lib/scientia_cognita_web/live/page/catalog_show_live.ex
  git commit -m "feat: migrate remaining LiveViews to waffle uploader"
  ```

---

## Task 12: Delete Storage Module and Run Full Test Suite

**Files:**
- Delete: `lib/scientia_cognita/storage.ex`

- [ ] **Step 1: Verify Storage is no longer referenced anywhere**

  Run: `grep -r "ScientiaCognita.Storage\|alias.*Storage" lib/ test/ --include="*.ex" --include="*.exs"`
  Expected: No output (zero matches).

  If any matches appear, fix them before proceeding.

- [ ] **Step 2: Delete the Storage module**

  ```bash
  git rm lib/scientia_cognita/storage.ex
  ```

- [ ] **Step 3: Compile**

  Run: `mix compile --warning-as-errors`
  Expected: Clean compile with zero warnings.

- [ ] **Step 4: Reset the database**

  Run: `mix ecto.reset`
  Expected: Database dropped, recreated, migrated. New migration creates `original_image`, `processed_image`, `final_image` columns.

- [ ] **Step 5: Run the full test suite**

  Run: `mix test`
  Expected: All tests pass.

  If any tests fail due to leftover `storage_key`/`processed_key` references that were missed, fix them now before committing.

- [ ] **Step 6: Final commit**

  ```bash
  git commit -m "feat: delete bespoke Storage module — fully migrated to waffle"
  ```
  (The `git rm` was already run in Step 2 — no need to repeat it here.)

---

## Task 13: Smoke Test in Dev

- [ ] **Step 1: Start MinIO** (if not already running)

  ```bash
  minio server ~/minio-data
  ```

- [ ] **Step 2: Start the app**

  ```bash
  mix phx.server
  ```
  Expected: Starts cleanly. The bucket existence check fires in the background log: no error about `ScientiaCognita.Storage`.

- [ ] **Step 3: Trigger an item through the pipeline**

  In the browser, navigate to `/console/sources`, create a source with a URL containing images, and start the crawl. Watch an item progress through `downloading → processing → color_analysis → render → ready`. Verify the thumbnail appears in `SourceShowLive` at each stage.

- [ ] **Step 4: Verify URL format**

  In the console, after an item reaches `ready`, inspect the rendered `src` attribute of an `<img>` tag. For dev it should be `http://localhost:9000/images/items/{id}/final.jpg`. Confirm the image loads.
