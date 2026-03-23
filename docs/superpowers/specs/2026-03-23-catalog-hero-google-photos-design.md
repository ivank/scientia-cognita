# Catalog Hero Banner & Google Photos Tracking — Design Spec

**Date:** 2026-03-23
**Status:** Approved

---

## Overview

Refactor the `CatalogShowLive` page to feature a prominent hero banner that displays the current user's Google Photos sync status for the catalog. Add persistent database tracking of album and item-level upload state per user, with per-item error visibility in the photo grid.

---

## 1. Database Schema

### New table: `photo_exports`

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer PK | |
| `user_id` | integer FK | references `users`, not null |
| `catalog_id` | integer FK | references `catalogs`, not null |
| `album_id` | string | Google Photos album ID, nullable until created |
| `album_url` | string | Shareable album URL, nullable |
| `status` | string | `pending` / `running` / `done` / `failed` / `deleted` |
| `error` | string | Album-level error message, nullable |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

Unique index on `(user_id, catalog_id)`.

### New table: `photo_export_items`

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer PK | |
| `photo_export_id` | integer FK | references `photo_exports`, not null |
| `item_id` | integer FK | references `items`, not null |
| `status` | string | `pending` / `uploaded` / `failed` |
| `error` | string | Item-level error message, nullable |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

Unique index on `(photo_export_id, item_id)`.

### Scoping

All queries for exports and export items include `where: pe.user_id == ^user_id`. No user ever sees another user's export data.

---

## 2. New Context: `ScientiaCognita.Photos`

Owns all DB access for the two new tables. Public API:

```elixir
get_export_for_user(user, catalog)             # returns %PhotoExport{} | nil
get_or_create_export(user, catalog)            # upsert, returns {:ok, export}
list_uploaded_item_ids(export)                 # [item_id, ...] already uploaded
set_export_status(export, status, opts \\ []) # updates status + optional error/album fields
set_item_uploaded(export, item)               # upserts photo_export_items with status: uploaded
set_item_failed(export, item, error)          # upserts photo_export_items with status: failed + error
delete_export(export)                          # sets status: deleted (DB only, worker handles API call)
list_export_item_statuses(export)              # %{item_id => %{status, error}} map
```

---

## 3. Updated `ExportAlbumWorker`

### Sync logic (handles both first export and re-sync)

1. Upsert `photo_export` row (`status: running`) via `Photos.get_or_create_export/2`
2. If `album_id` is nil: call Google Photos API to create album, persist `album_id` on the export
3. Load already-uploaded item IDs via `Photos.list_uploaded_item_ids/1`
4. For each catalog item **not** in that set:
   - Upload bytes to Google Photos
   - On success: call `Photos.set_item_uploaded/2`, broadcast progress
   - On failure: call `Photos.set_item_failed/3`, continue (don't abort entire job)
5. Batch-create media items in the album (50 per call)
6. Set export `status: done`, persist `album_url`, broadcast `:export_done`
7. On unrecoverable crash: set export `status: failed`, broadcast `:export_failed`

### PubSub topic

Changed from `"export:#{catalog_id}"` to `"export:#{catalog_id}:#{user_id}"` to prevent progress leaking across users viewing the same catalog simultaneously.

---

## 4. New `DeleteAlbumWorker`

```
queue: :export, max_attempts: 2
args: %{photo_export_id, user_id}
```

1. Load export, verify `export.user_id == user_id` (authorization guard)
2. Call `DELETE https://photoslibrary.googleapis.com/v1/albums/:album_id` with user's access token
3. On success: call `Photos.set_export_status(export, :deleted)`, broadcast `:export_deleted`
4. On failure: broadcast `:export_delete_failed` with error

### Required OAuth scope addition

Add `photoslibrary.edit.appcreateddata` to the Google OAuth redirect scopes (alongside existing `photoslibrary.appendonly`). This allows deleting only albums/items the app itself created.

---

## 5. Hero Banner UI — `CatalogShowLive`

### Layout

Full-width dark banner at the top of the catalog page, above the item grid. Color scheme and icon change per state.

### States

| State | Background | Icon | Primary action |
|-------|-----------|------|----------------|
| Not logged in | Dark slate (`#1e293b`) | 🔒 Lock | "Log in to save" (indigo button) |
| No Google Photos | Dark slate (`#1e293b`) | 📷 Camera | "Connect Google Photos" (amber button) |
| Ready (not yet exported) | Dark navy | ☁️ Cloud | "Save to Google Photos" (blue button, large) |
| Running | Dark navy | ⏳ Hourglass (pulsing) | Disabled "In progress…" + progress bar |
| Done | Dark green (`#052e16`) | ✅ Check | "Sync new items" + "Delete album" (red) |
| Failed | Dark red (`#2d0a0a`) | ⚠️ Warning | "Retry failed items" |

### Progress bar (Running state)

- Full width of the banner
- Height: 10px
- Animated gradient fill (`#3b82f6` → `#60a5fa`)
- Count label: "28 / 47 uploaded"
- Hourglass icon pulses (opacity + scale, 1.5s ease-in-out loop)

### Done state buttons

- **Sync new items** — enqueues `ExportAlbumWorker` (same upsert logic, skips already-uploaded)
- **Delete album** — opens confirmation modal (see Section 7)

### Not-logged-in permissions explanation

The "Connect Google Photos" state lists required permissions inline:

> 📁 Create & manage albums · ⬆️ Upload photos · 🗑️ Delete app albums

---

## 6. Item Grid — Error Badges

When the user has an active `photo_export`, error state is overlaid on grid items:

- **Uploaded** items: small green checkmark badge (bottom-right corner)
- **Failed** items: red border (2px `#ef4444`) + small "⚠ FAILED" badge (top-right corner), image dimmed to 50% opacity
- **Not-yet-uploaded** items: no indicator

Error detail is shown in the existing lightbox modal — a red error banner appears above the title/author info if `export_item.error` is present.

---

## 7. Delete Confirmation Modal

Triggered by the "Delete album" button in the Done-state hero.

DaisyUI modal containing:
- Title: "Delete album from Google Photos?"
- Body: "This will permanently delete the album **{catalog.name}** from your Google Photos library. The photos in this catalog will not be affected."
- Buttons: **Cancel** (ghost) / **Delete** (red, `btn-error`)

On confirm: enqueues `DeleteAlbumWorker`.

---

## 8. `CatalogShowLive` Mount Changes

```elixir
# On mount:
export = Photos.get_export_for_user(current_scope.user, catalog)
export_item_statuses = if export, do: Photos.list_export_item_statuses(export), else: %{}

Phoenix.PubSub.subscribe(PubSub, "export:#{catalog.id}:#{user.id}")

assign(socket,
  export: export,
  export_item_statuses: export_item_statuses,
  show_delete_confirm: false
)
```

Handles new PubSub messages: `:export_deleted`, `:export_delete_failed`.

On `:export_progress` / `:export_done` / `:export_failed`: update `export` assign by reloading from DB (or updating inline from message payload).

---

## 9. Out of Scope

- Exporting the same catalog to multiple albums per user (one album per user+catalog enforced by unique index)
- Removing photos from Google Photos when items are removed from a catalog
- Sharing album links with non-logged-in users
- Token refresh logic (existing token management unchanged)
