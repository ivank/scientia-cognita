# Waffle Storage Refactor Design

**Date:** 2026-03-22
**Status:** Approved

## Problem

The bespoke `ScientiaCognita.Storage` module wraps `ex_aws`/`ex_aws_s3` and manually constructs public URLs via string concatenation. In production (Tigris), this generates path-style URLs (`https://fly.storage.tigris.dev/images/key`) when Tigris requires virtual-hosted-style (`https://images.fly.storage.tigris.dev/key`). This causes `ProcessImageWorker`, `ColorAnalysisWorker`, and `RenderWorker` to receive 403/404s when fetching stored images between pipeline stages.

Additionally, `get_url/1` is called directly (not via the injected `@storage` module attribute), so the URL construction bug is not covered by any existing test.

## Goal

Replace the bespoke storage module with `waffle` + `waffle_ecto`, the standard Elixir file-upload library. Waffle delegates URL generation to ExAws's own config machinery, which handles path-style vs virtual-hosted-style correctly per environment. Three distinct Ecto attachment fields replace the two overloaded string columns.

## Approach

Single `ItemImageUploader` with one Waffle version (`:original` — no in-library transformations, workers handle processing). Three separate Ecto attachment fields on `Item` use the same uploader type. Storage path is `items/{item_id}/{filename}` where each pipeline stage supplies a specific filename (`original<ext>`, `processed.jpg`, `final.jpg`).

## Dependencies

Add to `mix.exs`:

```elixir
{:waffle, "~> 1.1"},
{:waffle_ecto, "~> 0.0.12"},
```

Retain `ex_aws`, `ex_aws_s3`, `sweet_xml`, `hackney` — Waffle delegates S3 operations to them.

Note: `waffle_ecto ~> 0.0.12` pins to the current stable series. The lock file will pin the exact version at `mix deps.get` time.

## Uploader Module

**`lib/scientia_cognita/uploaders/item_image_uploader.ex`**

```elixir
defmodule ScientiaCognita.Uploaders.ItemImageUploader do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]

  def storage_dir(_version, {_file, item}), do: "items/#{item.id}"
  def acl(_version, _), do: :public_read

  def bucket do
    Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
  end

  @doc """
  Ensures the configured bucket exists. Called at application startup.
  Moved here from the deleted Storage module.
  """
  def ensure_bucket_exists do
    b = bucket()

    case ExAws.S3.head_bucket(b) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        b |> ExAws.S3.put_bucket("us-east-1") |> ExAws.request()
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

Important: do **not** set `:waffle, :bucket` globally in any config file. The per-uploader `bucket/0` callback is the authoritative source; a global `:waffle, :bucket` value would shadow it.

## Configuration

Add to `config/config.exs`:

```elixir
config :waffle, storage: Waffle.Storage.S3
```

Add to `config/test.exs`:

```elixir
config :waffle, storage: Waffle.Storage.Local
config :waffle, storage_dir_prefix: "priv/waffle_test"
```

The per-environment ExAws config (`dev.exs`, `runtime.exs`) is unchanged — Waffle reads it automatically.

Delete the now-redundant `ScientiaCognita.Storage` and `ScientiaCognita.StorageBehaviour` modules.

## Schema Changes

### Migration

The existing `create_items` migration is **rewritten in place** (not a new file). This is valid because the database will be fully reset with `mix ecto.reset` before running again. Replace `storage_key :string` and `processed_key :string` with:

```elixir
add :original_image,  :string
add :processed_image, :string
add :final_image,     :string
```

> **Note for future team use:** If the database cannot be reset, generate a new migration that renames/drops the old columns and adds the new ones with a `down/0` rollback path instead.

### Item Schema

Replace:

```elixir
field :storage_key,   :string
field :processed_key, :string
```

With:

```elixir
field :original_image,  ItemImageUploader.Type
field :processed_image, ItemImageUploader.Type
field :final_image,     ItemImageUploader.Type
```

### FSM Transition Changesets

| Transition | Old field | New field |
|---|---|---|
| `downloading → processing` | `:storage_key` | `:original_image` |
| `processing → color_analysis` | `:processed_key` | `:processed_image` |
| `render → ready` | `:processed_key` (clobbered) | `:final_image` |

The `render → ready` transition previously clobbered `processed_key` with the final rendered image. With three distinct fields this overwrite is eliminated.

### `storage_changeset/2`

Update to cast `[:original_image, :processed_image, :final_image]` (used by test fixtures and the `redownload_item` / `rerender_item` flows to nil-clear fields).

Clearing a Waffle attachment: pass `nil` via `Ecto.Changeset.change/2` or `cast/3` — `Waffle.Ecto.Type` stores and retrieves nil correctly.

## Workers

### Dependency Injection

Each worker uses the compile-time attribute for both upload and URL generation (so URL generation is also testable via the mock):

```elixir
@uploader Application.compile_env(:scientia_cognita, :uploader_module,
            ScientiaCognita.Uploaders.ItemImageUploader)
```

### Upload Pattern

Workers operate on in-memory binary. Waffle accepts `%{binary: binary, file_name: "name.jpg"}` directly (Waffle writes to a temp file internally then uploads):

```elixir
upload = %{binary: binary, file_name: "original#{ext}"}
{:ok, file} = @uploader.store({upload, item})
# file is the Waffle file struct; used as the FSM transition param value
```

### URL Generation

All `Storage.get_url(key)` calls become `@uploader.url({file, item})`:

```elixir
url = @uploader.url({item.original_image, item})
# dev  → "http://localhost:9000/images/items/42/original.jpg"
# prod → "https://images.fly.storage.tigris.dev/items/42/original.jpg"
```

### `DownloadImageWorker`

- Remove `Storage` alias.
- `ext_from_content_type/1` is retained — extension is dynamic: `file_name: "original#{ext}"`.
- Upload: `@uploader.store({%{binary: binary, file_name: "original#{ext}"}, item})`.
- FSM transition params: `%{original_image: file}` (was `%{storage_key: key}`).

### `ProcessImageWorker`

- Remove `Storage` alias.
- Add `@uploader` attribute.
- `download_original/1` uses `@uploader.url({item.original_image, item})`.
- Upload: `@uploader.store({%{binary: output_binary, file_name: "processed.jpg"}, item})`.
- FSM transition params: `%{processed_image: file}`.

### `ColorAnalysisWorker`

- Remove `Storage` alias; currently calls `Storage.get_url/1` directly (not via `@storage`) — this is fixed by the `@uploader` injection.
- Add `@uploader` attribute.
- `download_processed/1` uses `@uploader.url({item.processed_image, item})`.
- Field reference: `item.processed_image` (was `item.processed_key`).

### `RenderWorker`

- Remove `Storage` alias.
- `download_processed/1` uses `@uploader.url({item.processed_image, item})`.
- Upload: `@uploader.store({%{binary: output_binary, file_name: "final.jpg"}, item})`.
- FSM transition params: `%{final_image: file}` (was clobbering `processed_key`).

### `ExportAlbumWorker`

- Remove `Storage` alias.
- `item.processed_key` nil-guards become `item.final_image` (export the final rendered image). Waffle stores nil when no file is present, so `& &1.final_image` has identical truthy/falsy semantics to the old string check.
- `fetch_image/1` takes the full item and calls `ItemImageUploader.url({item.final_image, item})` directly (no `@uploader` injection needed here since this worker is not unit-tested with a storage mock).

## Context: `ScientiaCognita.Catalog`

### `delete_source_with_storage/2`

Replace `Storage.delete/1` calls with Waffle deletion for all three fields:

```elixir
Enum.each(items, fn item ->
  if item.original_image,  do: ItemImageUploader.delete({item.original_image,  item})
  if item.processed_image, do: ItemImageUploader.delete({item.processed_image, item})
  if item.final_image,     do: ItemImageUploader.delete({item.final_image,     item})
end)
```

### `get_catalog_cover_url/1`

- Query filter: `not is_nil(i.final_image)` (was `not is_nil(i.processed_key)`).
- URL: `ItemImageUploader.url({item.final_image, item})`.

## LiveViews

All LiveViews call `Storage.get_url/1` in templates. Replace with `ItemImageUploader.url({file, item})`. The `Storage` alias is removed from each module.

### `SourceShowLive`

- Template `Storage.get_url(...)` calls replaced with `ItemImageUploader.url({field, @item})` or `ItemImageUploader.url({field, @selected_item})` as appropriate.
- `thumb_url/1` refactored to take the full item struct and **return the URL string** by calling `ItemImageUploader.url/1` internally. The `item_thumbnail/1` component uses `thumb_url(@item)` directly — the existing `Storage.get_url(thumb_url(@item))` wrapping call is removed.
- `thumb_type/1` pattern matches on `storage_key: nil` and `processed_key: pk` — update field names to `original_image` and `processed_image`/`final_image` respectively.
- `redownload_item` handler: clear via `Catalog.update_item_storage(item, %{original_image: nil, processed_image: nil, final_image: nil})`.
- `rerender_item` handler: **replace** the existing `Ecto.Changeset.change` fields — remove `processed_key: nil` and substitute `processed_image: nil, final_image: nil` (retains `original_image` since re-render starts from the stored original; `processed_key` no longer exists).
- Retry routing (`retry_failed_items`): `is_nil(item.storage_key)` → `is_nil(item.original_image)`, `is_nil(item.processed_key)` → `is_nil(item.processed_image)`. Waffle stores nil when no file is present, so nil-check semantics are identical.
- Re-render button `:if` guard: `not is_nil(@selected_item.storage_key)` → `not is_nil(@selected_item.original_image)`.

### `CatalogShowLive` (console), `SourcesLive`, `page/CatalogShowLive`

- Replace `Storage.get_url(item.processed_key)` with `ItemImageUploader.url({item.final_image, item})`.
- Replace `:if={item.processed_key}` nil guards with `:if={item.final_image}`.

## `application.ex`

Replace:

```elixir
Task.start(fn -> ScientiaCognita.Storage.ensure_bucket_exists() end)
```

With:

```elixir
Task.start(fn -> ScientiaCognita.Uploaders.ItemImageUploader.ensure_bucket_exists() end)
```

## Tests

### Behaviour + Mock

Replace `StorageBehaviour` / `StorageMock` with `UploaderBehaviour` / `MockUploader` (following the existing `MockHttp`, `MockGemini`, `MockStorage` naming convention):

```elixir
defmodule ScientiaCognita.UploaderBehaviour do
  @callback store(any()) :: {:ok, any()} | {:error, term()}
  @callback url(any()) :: String.t()
end
```

Both `store/1` and `url/1` are in the behaviour so Mox can stub both. No `delete/1` callback is needed in the behaviour — deletion is called directly on the uploader module (not injected), mirroring how the current `Catalog.delete_source_with_storage/1` does not use the mock.

### Config

```elixir
# test.exs
config :scientia_cognita, uploader_module: ScientiaCognita.MockUploader
```

### Test Cleanup

All unit tests for workers use `UploaderMock` via the injected `@uploader` attribute — no real files are written in unit tests. The `Waffle.Storage.Local` config is a safety net for any integration tests that bypass the mock. Add an `on_exit` cleanup to `DataCase`:

```elixir
on_exit(fn -> File.rm_rf!("priv/waffle_test") end)
```

## Files Changed

| Action | File |
|---|---|
| Add | `lib/scientia_cognita/uploaders/item_image_uploader.ex` |
| Delete | `lib/scientia_cognita/storage.ex` |
| Delete | `lib/scientia_cognita/storage_behaviour.ex` |
| Modify | `mix.exs` |
| Modify | `config/config.exs` |
| Modify | `config/test.exs` |
| Rewrite | migration for `items` table (`priv/repo/migrations/*_create_items.exs`) |
| Modify | `lib/scientia_cognita/catalog/item.ex` |
| Modify | `lib/scientia_cognita/workers/download_image_worker.ex` |
| Modify | `lib/scientia_cognita/workers/process_image_worker.ex` |
| Modify | `lib/scientia_cognita/workers/color_analysis_worker.ex` |
| Modify | `lib/scientia_cognita/workers/render_worker.ex` |
| Modify | `lib/scientia_cognita/workers/export_album_worker.ex` |
| Modify | `lib/scientia_cognita/catalog.ex` |
| Modify | `lib/scientia_cognita/application.ex` |
| Modify | `lib/scientia_cognita_web/live/console/source_show_live.ex` |
| Modify | `lib/scientia_cognita_web/live/console/sources_live.ex` |
| Modify | `lib/scientia_cognita_web/live/console/catalog_show_live.ex` |
| Modify | `lib/scientia_cognita_web/live/page/catalog_show_live.ex` |
| Modify | `test/support/mocks.ex` (or wherever mocks are defined) |
| Modify | `test/support/fixtures/catalog_fixtures.ex` (rename `storage_key`/`processed_key` to `original_image`/`processed_image`/`final_image` in `item_fixture/2`) |
| Modify | Worker test files |
