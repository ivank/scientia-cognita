# Waffle Storage Refactor Design

**Date:** 2026-03-22
**Status:** Approved

## Problem

The bespoke `ScientiaCognita.Storage` module wraps `ex_aws`/`ex_aws_s3` and manually constructs public URLs via string concatenation. In production (Tigris), this generates path-style URLs (`https://fly.storage.tigris.dev/images/key`) when Tigris requires virtual-hosted-style (`https://images.fly.storage.tigris.dev/key`). This causes `ProcessImageWorker` and `RenderWorker` to receive 403/404s when fetching stored images between pipeline stages.

## Goal

Replace the bespoke storage module with `waffle` + `waffle_ecto`, the standard Elixir file-upload library. Waffle delegates URL generation to ExAws's own config machinery, which handles path-style vs virtual-hosted-style correctly per environment. Three distinct Ecto attachment fields replace the two overloaded string columns.

## Approach

Single `ItemImageUploader` with one Waffle version (`:original` — no in-library transformations, workers handle processing). Three separate Ecto attachment fields on `Item` use the same uploader type. Storage path is `items/{item_id}/{filename}` where each pipeline stage supplies a specific filename (`original.jpg`, `processed.jpg`, `final.jpg`).

## Dependencies

- Add `{:waffle, "~> 1.1"}` and `{:waffle_ecto, "~> 0.0"}` to `mix.exs`.
- Retain `ex_aws`, `ex_aws_s3`, `sweet_xml`, `hackney` — Waffle delegates S3 operations to them.

## Uploader Module

**`lib/scientia_cognita/uploaders/item_image_uploader.ex`**

```elixir
defmodule ScientiaCognita.Uploaders.ItemImageUploader do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]

  def storage_dir(_version, {_file, item}), do: "items/#{item.id}"
  def acl(_version, _), do: :public_read
  def bucket, do: Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
end
```

- Reuses the existing `:scientia_cognita, :storage` bucket config — no duplication.
- No version transforms: each worker uploads fully-prepared binary.
- Files named by the worker (`original.jpg`, `processed.jpg`, `final.jpg`) yield distinct S3 keys within the same `items/{id}/` prefix.

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

### Migration (rewritten, not a new file)

Replace `storage_key :string` and `processed_key :string` with:

```elixir
add :original_image,  :string
add :processed_image, :string
add :final_image,     :string
```

No data preservation required — database will be reset.

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

The `render → ready` transition previously clobbered `processed_key` with the final rendered image. With three distinct fields this is no longer necessary.

### `storage_changeset/2`

Update to cast `[:original_image, :processed_image, :final_image]` (used by test fixtures).

## Workers

### Upload Pattern

Workers operate on in-memory binary. Waffle accepts `%{binary: binary, file_name: "name.jpg"}` directly:

```elixir
upload = %{binary: binary, file_name: "original.jpg"}
{:ok, file} = @uploader.store({upload, item})
# file is the Waffle file struct; cast into FSM transition params
```

### URL Generation

```elixir
url = ItemImageUploader.url({item.original_image, item})
# dev  → "http://localhost:9000/images/items/42/original.jpg"
# prod → "https://images.fly.storage.tigris.dev/items/42/original.jpg"
```

### Worker-specific changes

**`DownloadImageWorker`:**
- Remove `Storage` alias.
- Upload with `file_name: "original#{ext}"`.
- FSM transition params: `%{original_image: file}` (was `%{storage_key: key}`).
- `download_original/1` replaced by `@uploader.url/1`.

**`ProcessImageWorker`:**
- Remove `Storage` alias.
- `download_original/1` uses `@uploader.url({item.original_image, item})`.
- Upload with `file_name: "processed.jpg"`.
- FSM transition params: `%{processed_image: file}`.

**`RenderWorker`:**
- Remove `Storage` alias.
- `download_processed/1` uses `@uploader.url({item.processed_image, item})`.
- Upload with `file_name: "final.jpg"`.
- FSM transition params: `%{final_image: file}` (was clobbering `processed_key`).

### Dependency Injection

Each worker keeps the compile-time module attribute pattern:

```elixir
@uploader Application.compile_env(:scientia_cognita, :uploader_module,
            ScientiaCognita.Uploaders.ItemImageUploader)
```

## Tests

### Behaviour + Mock

Replace `StorageBehaviour` / `StorageMock` with `UploaderBehaviour` / `UploaderMock`:

```elixir
defmodule ScientiaCognita.UploaderBehaviour do
  @callback store(any()) :: {:ok, any()} | {:error, term()}
  @callback url(any()) :: String.t()
end
```

Worker tests inject `UploaderMock` via `config :scientia_cognita, uploader_module: UploaderMock`.

### Test Cleanup

Add an `on_exit` hook in test setup to delete files under `priv/waffle_test/` when `Waffle.Storage.Local` is active. (Only relevant if integration tests call `store/1` without mocking.)

## Files Changed

| Action | File |
|---|---|
| Add | `lib/scientia_cognita/uploaders/item_image_uploader.ex` |
| Delete | `lib/scientia_cognita/storage.ex` |
| Delete | `lib/scientia_cognita/storage_behaviour.ex` |
| Modify | `mix.exs` |
| Modify | `config/config.exs` |
| Modify | `config/test.exs` |
| Rewrite | migration for `items` table |
| Modify | `lib/scientia_cognita/catalog/item.ex` |
| Modify | `lib/scientia_cognita/workers/download_image_worker.ex` |
| Modify | `lib/scientia_cognita/workers/process_image_worker.ex` |
| Modify | `lib/scientia_cognita/workers/render_worker.ex` |
| Modify | `test/support/mocks.ex` (or wherever mocks are defined) |
| Modify | worker test files |
