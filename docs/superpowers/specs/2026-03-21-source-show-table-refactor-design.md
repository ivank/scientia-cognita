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
- Load source with `Catalog.get_source!(id)` (`gemini_pages` is an embedded schema, always present on the struct — no join/preload needed)
- Load all items with `Catalog.list_items_by_source(source)`
- Initialise items as a LiveView stream: `stream(:items, all_items)`
- Compute initial `status_counts`, `failed_count`, and `stuck_ids`
- Subscribe to `"source:#{id}"` PubSub topic

### PubSub handlers

**`{:source_updated, source}`** — broadcasted struct includes `gemini_pages`, no DB reload needed:
- `source` ← received struct
- `status_counts` ← `Catalog.count_items_by_status(source)` (scoped by `source.id`)
- `failed_count` ← `status_counts["failed"] || 0`
- `stuck_ids` ← `Catalog.list_stuck_item_ids(source) |> MapSet.new()`

**`{:item_updated, item}`**:
- `stream_insert(socket, :items, item)` — patches only the changed row in the DOM
- Issue a DB query: `status_counts` ← `Catalog.count_items_by_status(socket.assigns.source)` (a `GROUP BY status` query against all persisted items for `source.id` — the count is authoritative from the DB, independent of stream contents)
- `failed_count` ← `status_counts["failed"] || 0`
- Issue a DB query: `stuck_ids` ← `Catalog.list_stuck_item_ids(socket.assigns.source) |> MapSet.new()`

### Assigns
- `source` — the source struct (includes `gemini_pages`)
- `status_counts` — `%{status => count}` map
- `failed_count` — integer, always derived from `status_counts["failed"] || 0`
- `stuck_ids` — `MapSet` of item IDs stuck without active Oban jobs; refreshed on both handlers
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
| Status | status badge + optional `discarded` badge for stuck items (see below) |
| Title | item title, truncated |
| Description | description text; if `failed`, shows error in `text-error text-xs` |

### Stuck Items
Items whose ID is in `stuck_ids` show an additional `badge badge-warning badge-sm` labelled "discarded" next to the status badge in the Status column. This indicates the Oban job was discarded without marking the item failed. Logic and detection (`Catalog.list_stuck_item_ids/1`) are unchanged from the current implementation.

### Thumbnail Rules

Rules are **strict top-down first-match predicates** (like Elixir function clauses — the first matching rule wins, no subsequent rules are evaluated).

`processed_key` serves dual purposes: 16:9 FHD intermediate during `processing`/`color_analysis`/`render`, and final rendered image at `ready`. Both cases correctly display `processed_key`.

FSM invariants:
- `storage_key` is always set by the time an item reaches `processing` or any later state (set on `downloading → processing`).
- `processed_key` is always set by the time an item reaches `color_analysis` or any later state (set on `processing → color_analysis`; not cleared until `render → ready` overwrites it with the final rendered image).

Because `render` items always have `processed_key` (set at `color_analysis`, present through `render`), Rule 4 below must appear **before** the generic Rule 5 (`processed_key` present) so the animate-pulse ring fires for render-state items rather than the plain Rule 5 match. The `failed`-specific Rules 2–3 also appear before the generic key rules for the same reason.

`failed` items with `processed_key` will display that intermediate image as their thumbnail. This is intentional — the `bg-error/10` row background and the error text in the Description column already clearly signal the failed state; showing the available image gives useful context.

| Rule | Condition | Display |
|---|---|---|
| 1 | `pending` or `downloading` | DaisyUI `skeleton` shimmer |
| 2 | `failed` AND no `storage_key` | `hero-photo` icon on `bg-base-300`, 76×48 |
| 3 | `failed` AND has image keys | Best available: `processed_key` if set, else `storage_key` (no ring — row background signals failed state) |
| 4 | `render` (always has `processed_key` per invariant above) | `processed_key` image with `ring-2 ring-primary animate-pulse` |
| 5 | `processed_key` present | `processed_key` image |
| 6 | `storage_key` present | `storage_key` image |
| 7 | (fallback) | shimmer |

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
| Button | Visible when | Behaviour |
|---|---|---|
| Re-download | terminal state (`ready` or `failed`) | See steps below |
| Re-render | terminal state AND `storage_key` present | See steps below |
| Save | always | Saves changeset |
| Cancel | always | Closes modal |

Both Re-download and Re-render are **hidden** (not just disabled) when the item is in an active (non-terminal) state, to prevent duplicate job enqueue and race conditions.

### Note on FSM and administrative resets
Both re-trigger operations use **direct status writes** (via `Catalog.update_item_status/3` → `Item.status_changeset/3`) rather than FSM transitions. This is intentional: `ready → pending` and `failed/ready → processing` are not named FSM transitions. Direct writes are used for administrative resets, consistent with the existing `retry_item` and `retry_failed_items` handlers.

### Re-download steps
1. `Catalog.update_item_storage(item, %{storage_key: nil, processed_key: nil})`
2. `Catalog.update_item_status(item, "pending", error: nil)`
3. Enqueue `DownloadImageWorker` with `%{item_id: item.id}`

### Re-render steps
1. `Catalog.update_item_storage(item, %{processed_key: nil})` — clear rendered output, preserve `storage_key`
2. `Catalog.update_item_status(item, "processing", error: nil)`
3. Enqueue `ProcessImageWorker` with `%{item_id: item.id}`

`storage_key` is preserved as the input for `ProcessImageWorker`. That worker processes the image and transitions the item to `color_analysis`, whose worker then transitions to `render`, whose worker then transitions to `ready` — completing the pipeline without any further intervention from the LiveView.

---

## 5. Loading Banner

Shown when `source.status == "items_loading"`. A simple banner above the table:

```
[spinner] Items are being loaded…
```

Disappears automatically when a `{:source_updated, source}` message delivers a source with status `"done"` or `"failed"`.

---

## 6. Collapsible Gemini Panels

Placed below the items table. One `<details>` element per entry in `source.gemini_pages`.

`gemini_pages` is an embedded schema always present on the struct — no additional queries needed.

### Collapsed (summary line)
```
Page N · gallery_title — gallery_description (truncated to ~80 chars) · M items
```
N is the 1-based index; M is `page.items_count`.

### Expanded
A `<pre class="text-xs overflow-auto max-h-96 bg-base-200 rounded p-3">` block with the full JSON. Because `GeminiPageResult` is an Ecto embedded schema struct (not directly Jason-encodable without a protocol implementation), convert it to a plain map first:

```elixir
case Jason.encode(Map.from_struct(page), pretty: true) do
  {:ok, json} -> json
  {:error, _} -> inspect(page)
end
```

`Map.from_struct/1` strips the `__struct__` key, leaving a plain map of primitive fields and `raw_items` (already `[map()]`). The `inspect/1` fallback handles any unexpected encoding failure gracefully.

---

## 7. Removed Behaviour

- **Stat cards** (pages fetched, items found, ready count, failed count) — removed
- **Ready items gallery** — removed (unified table replaces it)
- **Separate failed items table** — removed (unified table replaces it)
- **View mode in item modal** — removed (always edit mode)

---

## 8. Unchanged Behaviour

- Source-level actions: Restart, Retry failed items, Delete
- Progress bar and per-status breakdown (logic unchanged; data sourced from `status_counts` maintained via the new PubSub handlers rather than reloading all items)
- Delete confirmation modal
- Stuck items detection logic (`Catalog.list_stuck_item_ids/1`) and `discarded` badge rendering
- PubSub subscription and broadcast pattern
