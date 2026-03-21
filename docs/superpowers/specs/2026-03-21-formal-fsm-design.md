# Formal FSM Design: Source & Item Lifecycle

**Date:** 2026-03-21
**Status:** Approved

## Overview

Replace the hand-rolled `SourceFSM` / `ItemFSM` pattern-match modules with `fsmx`, an Ecto-integrated state machine library. This makes each state transition formally declared on the schema, enforces required data per transition via `transition_changeset/4` callbacks, and commits status changes + field updates atomically via `Ecto.Multi`. Add Elixir 1.19 native typed struct annotations throughout. Add an embedded `GeminiPageResult` schema capturing the full Gemini extraction output per page. Improve `HTMLStripper` to reduce token usage. Add a full-pipeline integration test using the Hubble fixture.

---

## 1. Dependencies

Add to `mix.exs`:
```elixir
{:fsmx, "~> 0.4"}
```

---

## 2. State Machines

### Source FSM

```
pending → fetching → extracting → items_loading → done
        ↘          ↘            ↘               ↘
        failed     failed       failed           (terminal)
failed is reachable from any non-terminal state
```

| State | Meaning |
|---|---|
| `pending` | Source created, not yet started |
| `fetching` | `FetchPageWorker` is fetching the initial HTML |
| `extracting` | `ExtractPageWorker` is calling Gemini per page; self-loops while paginating |
| `items_loading` | All pages scraped, all item jobs enqueued; waiting for item pipeline to complete |
| `done` | All items are `ready` or `failed`; triggered by the last `RenderWorker` |
| `failed` | Unrecoverable error at any stage |

### Item FSM

```
pending → downloading → processing → color_analysis → render → ready
        ↘            ↘            ↘               ↘        ↘
        failed       failed       failed           failed   (terminal)
```

| State | Meaning |
|---|---|
| `pending` | Item created by `ExtractPageWorker`, download not yet started |
| `downloading` | `DownloadImageWorker` fetching the original image |
| `processing` | `ProcessImageWorker` resizing / normalising |
| `color_analysis` | `ColorAnalysisWorker` calling Gemini for text/bg colours |
| `render` | `RenderWorker` compositing the final image |
| `ready` | Item fully processed and renderable |
| `failed` | Unrecoverable error at any stage |

---

## 3. fsmx Integration

Both `Source` and `Item` use `use Fsmx.Ecto`. The `transitions` map is declared on the schema. Each transition has a `transition_changeset/4` callback that casts and validates the data fields required for that specific transition. Workers call `Fsmx.transition_multi/4` which returns an `Ecto.Multi` — validated transition + field writes happen in one `Repo.transaction/1`.

### Source transition_changeset examples

```elixir
# pending → fetching: no extra fields required
def transition_changeset(changeset, "pending", "fetching", _params), do: changeset

# fetching → extracting: raw_html is required
def transition_changeset(changeset, "fetching", "extracting", params) do
  changeset
  |> cast(params, [:raw_html])
  |> validate_required([:raw_html])
end

# extracting → extracting (pagination self-loop): appends a GeminiPageResult
def transition_changeset(changeset, "extracting", "extracting", params) do
  changeset
  |> cast(params, [:pages_fetched, :total_items, :next_page_url])
  |> put_embed_append(:gemini_pages, params[:gemini_page])
end

# extracting → items_loading: first-page title/description set if not already present
def transition_changeset(changeset, "extracting", "items_loading", params) do
  changeset
  |> cast(params, [:pages_fetched, :total_items, :title, :description])
  |> put_embed_append(:gemini_pages, params[:gemini_page])
end

# items_loading → done: no extra fields required
def transition_changeset(changeset, "items_loading", "done", _params), do: changeset

# Any → failed: requires error message
def transition_changeset(changeset, _old, "failed", params) do
  changeset
  |> cast(params, [:error])
  |> validate_required([:error])
end
```

### Item transition_changeset examples

```elixir
# downloading → processing: storage_key required
def transition_changeset(changeset, "downloading", "processing", params) do
  changeset
  |> cast(params, [:storage_key])
  |> validate_required([:storage_key])
end

# processing → color_analysis: processed_key required
def transition_changeset(changeset, "processing", "color_analysis", params) do
  changeset
  |> cast(params, [:processed_key])
  |> validate_required([:processed_key])
end

# color_analysis → render: text_color, bg_color, bg_opacity all required
def transition_changeset(changeset, "color_analysis", "render", params) do
  changeset
  |> cast(params, [:text_color, :bg_color, :bg_opacity])
  |> validate_required([:text_color, :bg_color, :bg_opacity])
end

# render → ready: no extra fields required
def transition_changeset(changeset, "render", "ready", _params), do: changeset
```

### Worker usage pattern

```elixir
# Before (two separate calls, not atomic):
with {:ok, "fetching"} <- SourceFSM.transition(source, :start),
     {:ok, source}     <- Catalog.update_source_status(source, "fetching"),
     ...

# After (atomic):
with {:ok, multi}             <- Fsmx.transition_multi(source, "fetching", %{}),
     {:ok, %{transition: source}} <- Repo.transaction(multi),
     ...
```

`SourceFSM` and `ItemFSM` modules are deleted. Their unit tests are replaced by fsmx integration at the schema level.

---

## 4. Source Schema Changes

### Field renames
- `gallery_title` → `title` (editable via UI; populated from first Gemini result)
- `gallery_description` → `description` (editable via UI; populated from first Gemini result)

### New field
- `gemini_pages` — `embeds_many :gemini_pages, GeminiPageResult` stored as JSON; one entry appended per page processed by `ExtractPageWorker`

### New state
- `items_loading` added to `@statuses`

### Type annotations (Elixir 1.19)

```elixir
@type status :: String.t()
# valid values: "pending" | "fetching" | "extracting" | "items_loading" | "done" | "failed"

@type t :: %__MODULE__{
  id:            integer() | nil,
  url:           String.t(),
  name:          String.t(),
  status:        status(),
  title:         String.t() | nil,
  description:   String.t() | nil,
  raw_html:      String.t() | nil,
  next_page_url: String.t() | nil,
  pages_fetched: non_neg_integer(),
  total_items:   non_neg_integer(),
  error:         String.t() | nil,
  gemini_pages:  [GeminiPageResult.t()],
  items:         [Item.t()] | Ecto.Association.NotLoaded.t(),
  inserted_at:   DateTime.t() | nil,
  updated_at:    DateTime.t() | nil
}
```

---

## 5. GeminiPageResult Embedded Schema

New module `ScientiaCognita.Catalog.GeminiPageResult`.

```elixir
@primary_key false
embedded_schema do
  field :page_url,            :string
  field :is_gallery,          :boolean
  field :gallery_title,       :string   # original read-only Gemini output
  field :gallery_description, :string   # original read-only Gemini output
  field :next_page_url,       :string
  field :items_count,         :integer
  field :raw_items,           {:array, :map}  # full item array from Gemini
  field :generated_at,        :utc_datetime
end

@type t :: %__MODULE__{
  page_url:            String.t(),
  is_gallery:          boolean(),
  gallery_title:       String.t() | nil,
  gallery_description: String.t() | nil,
  next_page_url:       String.t() | nil,
  items_count:         non_neg_integer(),
  raw_items:           [map()],
  generated_at:        DateTime.t()
}
```

Stored in the `gemini_pages` JSON column on `sources`. `title` and `description` on `Source` are populated from the first page's `gallery_title` / `gallery_description` but remain independently editable.

---

## 6. items_loading → done Completion

`RenderWorker`, after marking an item as `ready`, checks completion:

```elixir
# After transitioning item to "ready":
source = Catalog.get_source!(item.source_id)
if source.status == "items_loading" do
  pending_count = Catalog.count_items_not_terminal(source)
  if pending_count == 0 do
    {:ok, multi} = Fsmx.transition_multi(source, "done", %{})
    Repo.transaction(multi)
  end
end
```

`count_items_not_terminal/1` queries `WHERE source_id = ? AND status NOT IN ('ready', 'failed')`. No counter cache. The last item to complete triggers the transition naturally.

---

## 7. HTMLStripper Improvements

Current problem: 649KB raw Hubble page hits the 300KB truncation ceiling after stripping, because `class`/`id` attributes are kept on every element.

Improvements (in application order):

| Step | Change | Expected reduction |
|---|---|---|
| 1 | Extract `<body>` only — discard `<head>` entirely | ~15-30KB |
| 2 | Drop `class` and `id` from all elements | ~100-150KB |
| 3 | Add `data-src`, `data-srcset`, `data-lazy-src` to img/figure keep-list | (additive, small) |
| 4 | Remove `<svg>` and all descendants (`path`, `use`, `defs`, `symbol`, etc.) | ~20-50KB |
| 5 | Remove HTML comments | ~5-10KB |
| 6 | Lower `max_bytes` from 300KB → 80KB | safety cap |

Target: stripped Hubble page well under 100KB, no truncation, Gemini correctly extracts 40 items with srcset-based absolute URLs.

---

## 8. Migration

One migration:
- Rename column `gallery_title` → `title`
- Rename column `gallery_description` → `description`
- Add column `gemini_pages` (text/JSON, nullable, default `[]`)
- No schema change needed for `items_loading` — it's a string enum enforced at app layer

---

## 9. Integration Test

File: `test/scientia_cognita/integration/source_lifecycle_test.exs`

### Layer 1 — Mocked (runs in CI)

Uses `hubble_page.html` as real HTML input through the real HTMLStripper. Gemini is mocked to return a canned 40-item response.

**Happy path (single page):**
1. `perform FetchPageWorker` → assert `source.status == "extracting"`, `raw_html` saved
2. `perform ExtractPageWorker` → assert:
   - `source.gemini_pages` has 1 entry with `items_count: 40` and full `raw_items`
   - `source.title` / `source.description` populated from Gemini result
   - `source.status == "items_loading"`
   - 40 `DownloadImageWorker` jobs enqueued
3. For each of 40 items, perform `DownloadImageWorker`, `ProcessImageWorker`, `ColorAnalysisWorker`, `RenderWorker`
4. After last `RenderWorker`: assert all items `ready`, `source.status == "done"`

**Paginated source (2 pages):**
- First `ExtractPageWorker` run: status stays `"extracting"`, next page enqueued
- Second run: status → `"items_loading"`

**Error paths:**
- `not_gallery` Gemini response → `source.status == "failed"`, descriptive error
- HTTP error during fetch → `source.status == "failed"`
- Gemini API error → `source.status == "failed"`
- Invalid transition attempted → gracefully ignored (`:ok` returned, no crash)

### Layer 2 — Live (`@moduletag :live`)

Uses real Gemini API. Validates HTMLStripper iteration during development:
```
raw hubble_page.html → HTMLStripper.strip/1 → real Gemini → assert 40 items, is_gallery=true
```

Run with: `mix test --include live test/scientia_cognita/integration/source_lifecycle_test.exs`

---

## 10. Files Affected

| File | Change |
|---|---|
| `mix.exs` | Add `fsmx` dep |
| `lib/.../catalog/source.ex` | Add fsmx, rename fields, add embeds_many, typed struct, `items_loading` state |
| `lib/.../catalog/item.ex` | Add fsmx, typed struct, transition_changeset callbacks |
| `lib/.../catalog/gemini_page_result.ex` | **New** — embedded schema |
| `lib/.../source_fsm.ex` | **Delete** |
| `lib/.../item_fsm.ex` | **Delete** |
| `lib/.../html_stripper.ex` | Strip body-only, drop class/id, add data-src, remove svg, comments |
| `lib/.../workers/fetch_page_worker.ex` | Use `Fsmx.transition_multi` |
| `lib/.../workers/extract_page_worker.ex` | Use `Fsmx.transition_multi`, save `GeminiPageResult` |
| `lib/.../workers/render_worker.ex` | After item→ready, check source completion |
| `priv/repo/migrations/YYYYMMDD_formal_fsm.exs` | **New** — rename columns, add gemini_pages |
| `test/.../integration/source_lifecycle_test.exs` | **New** — full pipeline integration test |
| `test/.../source_fsm_test.exs` | **Delete** (replaced by schema-level tests) |
| `test/.../item_fsm_test.exs` | **Delete** (replaced by schema-level tests) |
| `test/support/fixtures/catalog_fixtures.ex` | Update fixtures for renamed fields |
