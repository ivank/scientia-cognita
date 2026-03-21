# Source Show Page — Table Refactor Design

**Date:** 2026-03-21
**Scope:** `SourceShowLive` (`/console/sources/:id`)

---

## Overview

Replace the current split layout (ready-items gallery + failed-items table) with a unified, stream-backed items table showing all items regardless of status. Add collapsible Gemini extraction panels per crawled page. Fix re-render to use the original downloaded image rather than the final rendered image.

---

## 1. Page Layout

```
[Header: source name, status badge, action buttons]
[Source error alert — visible if source.error present]
[Progress bar — ready/total with per-status breakdown]
[Loading banner — visible when source.status == "items_loading"]
[Items table — all items, all statuses]
[Gemini extraction panels — one <details> per gemini_page entry]
[Item edit modal]
[Delete confirmation modal]
```

The stat cards (pages fetched, items found, ready, failed count) are removed.

---

## 2. Live Data Strategy

### Mount
- Load source with `Catalog.get_source!(id)` (gemini_pages embedded, no extra query needed)
- Load all items with `Catalog.list_items_by_source(source)`
- Initialise items as a LiveView stream: `stream(:items, all_items)`
- Compute initial `status_counts` and `stuck_ids` as before
- Subscribe to `"source:#{id}"` PubSub topic

### PubSub handlers
- `{:source_updated, source}` — update `source`, `status_counts`, `failed_count` in assigns (reload source from DB to get updated gemini_pages)
- `{:item_updated, item}` — call `stream_insert(socket, :items, item)` + refresh `status_counts` via `Catalog.count_items_by_status(source)`

### Assigns
- `source` — the source struct (includes `gemini_pages`)
- `status_counts` — `%{status => count}` map
- `failed_count` — integer
- `stuck_ids` — `MapSet` of item IDs stuck without active Oban jobs
- `selected_item` — the item open in the edit modal, or `nil`
- `item_form` — the `Phoenix.HTML.Form` for the edit modal, or `nil`
- `show_delete_modal` — boolean

Items live in the stream (`@streams.items`), not in assigns.

---

## 3. Items Table

### Columns
| Column | Content |
|---|---|
| Thumbnail | 76×48 px fixed, 16:9, see thumbnail rules below |
| Status | `status_badge` component (unchanged) |
| Title | item title, truncated |
| Description | description text; if `failed`, shows error in `text-error text-xs` |

### Thumbnail Rules (evaluated in order)
1. `pending` or `downloading` and no image keys → DaisyUI `skeleton` shimmer
2. `failed` with no `storage_key` → `hero-photo` icon centred on `bg-base-300` (same 76×48 dimensions)
3. `render` status with `processed_key` → show `processed_key` image with `ring-2 ring-primary animate-pulse` overlay to signal active rendering
4. `processed_key` present → show `processed_key` image
5. `storage_key` present → show `storage_key` image
6. Fallback → shimmer

### Row Background Colours
| Status(es) | Class |
|---|---|
| `pending`, `downloading` | `bg-base-200` |
| `processing`, `color_analysis`, `render` | `bg-info/10` |
| `ready` | `bg-success/10` |
| `failed` | `bg-error/10` |

### Row Interaction
Every row is clickable (`phx-click="select_item"`) regardless of status. Clicking opens the item edit modal directly (no view-only state).

---

## 4. Item Edit Modal

### Always Opens in Edit Mode
No view/edit toggle. The modal always renders the edit form.

### Error Display
If `item.error` is set, display it above the form as an `alert alert-error` block with the full (untruncated) error text.

### Form Fields
- Title
- Description (textarea)
- Image URL (`original_url`)

### Action Buttons
| Button | Condition | Behaviour |
|---|---|---|
| Re-download | always visible | Clears `storage_key` + `processed_key`, resets status to `"pending"`, enqueues `DownloadImageWorker` |
| Re-render | visible only if `storage_key` present | Clears `processed_key`, resets status to `"processing"`, enqueues `ProcessImageWorker` — uses original downloaded image as base, runs full process → color_analysis → render chain |
| Save | always | Saves changeset |
| Cancel | always | Closes modal |

### Re-render Implementation Change
Current `rerender_item` handler puts the item into `"render"` state and enqueues `RenderWorker` using `processed_key` (which is the final rendered image after ready — wrong source).

New behaviour:
1. `Catalog.update_item_storage(item, %{processed_key: nil})` — clear rendered output
2. `Catalog.update_item_status(item, "processing", error: nil)`
3. Enqueue `ProcessImageWorker` with `%{item_id: item.id}`

`storage_key` (the original downloaded image) is preserved and used as the input for `ProcessImageWorker`.

---

## 5. Loading Banner

Shown when `source.status == "items_loading"`. A simple banner above the table:

```
[spinner] Items are being loaded…
```

Disappears automatically when a `{:source_updated, source}` message sets status to `"done"` or `"failed"`.

---

## 6. Collapsible Gemini Panels

Placed below the items table. One `<details>` element per entry in `source.gemini_pages`.

### Collapsed (summary)
```
Page N · gallery_title — gallery_description (truncated to ~80 chars) · M items
```

### Expanded
A `<pre class="text-xs overflow-auto max-h-96 bg-base-200 rounded p-3">` containing the full JSON of that `GeminiPageResult`, rendered via `Jason.encode!(page, pretty: true)`.

No changes to the data layer are needed — `gemini_pages` is already an embedded schema loaded with every `get_source!` call.

---

## 7. Removed Behaviour

- **Stat cards** (pages fetched, items found, ready count, failed count) — removed
- **Ready items gallery** — removed (unified table replaces it)
- **Separate failed items table** — removed (unified table replaces it)
- **View mode in item modal** — removed (always edit mode)

---

## 8. Unchanged Behaviour

- Source-level actions: Restart, Retry failed items, Delete (unchanged)
- Progress bar and per-status breakdown
- Delete confirmation modal
- Stuck items detection (`stuck_ids` MapSet shown via `discarded` badge in status column)
- PubSub subscription and broadcast pattern
- `DownloadImageWorker` re-download path (unchanged)
