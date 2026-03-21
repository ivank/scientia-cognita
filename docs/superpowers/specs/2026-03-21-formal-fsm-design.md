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
        ↘          ↘   ↑        ↘
        failed    failed|      failed
                  (self-loop while paginating)
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

Both `Source` and `Item` use `use Fsmx.Ecto`. The `transitions` map declares all valid `from → [to]` edges. Each transition has a `transition_changeset/4` callback that casts and validates required fields for that specific transition. Workers build an `Ecto.Multi`, pipe it through `Fsmx.transition_multi/5`, then commit with `Repo.transaction/1` — validated transition + field writes happen atomically.

### Source transitions map

```elixir
use Fsmx.Ecto,
  transitions: %{
    "pending"       => ["fetching", "failed"],
    "fetching"      => ["extracting", "failed"],
    "extracting"    => ["extracting", "items_loading", "failed"],  # self-loop for pagination
    "items_loading" => ["done", "failed"]
  }
```

The `"extracting" => ["extracting", ...]` entry explicitly enables the pagination self-loop. fsmx requires all valid target states to be declared here; without it, `extracting → extracting` would be rejected as an invalid transition.

### Item transitions map

```elixir
use Fsmx.Ecto,
  transitions: %{
    "pending"        => ["downloading", "failed"],
    "downloading"    => ["processing", "failed"],
    "processing"     => ["color_analysis", "failed"],
    "color_analysis" => ["render", "failed"],
    "render"         => ["ready", "failed"]
  }
```

### GeminiPageResult construction

Workers always build a `%GeminiPageResult{}` struct via a `GeminiPageResult.new/1` constructor
before passing it to `transition_changeset`. The constructor computes `items_count` as
`length(raw_items)` — it is never accepted as an independent input:

```elixir
def new(attrs) do
  %GeminiPageResult{
    page_url:            attrs.page_url,
    is_gallery:          attrs.is_gallery,
    gallery_title:       attrs.gallery_title,
    gallery_description: attrs.gallery_description,
    next_page_url:       attrs.next_page_url,
    raw_items:           attrs.raw_items,
    items_count:         length(attrs.raw_items),   # always derived, never caller-supplied
    generated_at:        DateTime.utc_now(:second)
  }
end
```

`GeminiPageResult` also exposes a `changeset/2` function so that `put_embed/3` can cast it:

```elixir
def changeset(result, attrs) do
  result
  |> cast(attrs, [:page_url, :is_gallery, :gallery_title, :gallery_description,
                  :next_page_url, :items_count, :raw_items, :generated_at])
end
```

The `params[:gemini_page]` value passed into every `transition_changeset` callback is always
a `%GeminiPageResult{}` struct (built via `new/1`), never a raw map. `put_embed/3` on an
`embeds_many` with `@primary_key false` re-casts the full list through `changeset/2`; passing
structs here ensures clean round-trips.

### Source transition_changeset callbacks

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
  existing = get_field(changeset, :gemini_pages) || []
  changeset
  |> cast(params, [:pages_fetched, :total_items, :next_page_url])
  |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
end

# extracting → items_loading: appends final GeminiPageResult, sets title/description.
# title/description are unconditionally overwritten from the first Gemini page result.
# UI edits are the user's responsibility; re-running extraction resets them.
def transition_changeset(changeset, "extracting", "items_loading", params) do
  existing = get_field(changeset, :gemini_pages) || []
  changeset
  |> cast(params, [:pages_fetched, :total_items, :title, :description])
  |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
end

# items_loading → done: no extra fields required
def transition_changeset(changeset, "items_loading", "done", _params), do: changeset

# Any → failed: requires error message; covers all non-terminal → failed transitions
# including items_loading → failed
def transition_changeset(changeset, _old, "failed", params) do
  changeset
  |> cast(params, [:error])
  |> validate_required([:error])
end
```

### Item transition_changeset callbacks

```elixir
# pending → downloading: no extra fields required
def transition_changeset(changeset, "pending", "downloading", _params), do: changeset

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

# color_analysis → render: all three colour fields required
def transition_changeset(changeset, "color_analysis", "render", params) do
  changeset
  |> cast(params, [:text_color, :bg_color, :bg_opacity])
  |> validate_required([:text_color, :bg_color, :bg_opacity])
end

# render → ready: no extra fields required
def transition_changeset(changeset, "render", "ready", _params), do: changeset

# Any → failed: requires error message
def transition_changeset(changeset, _old, "failed", params) do
  changeset
  |> cast(params, [:error])
  |> validate_required([:error])
end
```

### Worker usage pattern

`Fsmx.transition_multi/5` signature: `(multi, schema, multi_key, new_state, params \\ %{})`.
It returns an `Ecto.Multi` (not `{:ok, multi}`). `Repo.transaction/1` returns `{:ok, %{multi_key => updated_struct}}`.

```elixir
# Before (two separate calls, not atomic):
with {:ok, "fetching"} <- SourceFSM.transition(source, :start),
     {:ok, source}     <- Catalog.update_source_status(source, "fetching"),
     ...

# After (atomic):
multi =
  Ecto.Multi.new()
  |> Fsmx.transition_multi(source, :transition, "fetching", %{})

with {:ok, %{transition: source}} <- Repo.transaction(multi),
     ...
```

`SourceFSM` and `ItemFSM` modules are deleted. Their unit tests are replaced by fsmx integration at the schema level.

---

## 4. Source Schema Changes

### Field renames
- `gallery_title` → `title` (editable via UI; populated from first page's Gemini `gallery_title`)
- `gallery_description` → `description` (editable via UI; populated from first page's Gemini `gallery_description`)

### New field
- `gemini_pages` — `embeds_many :gemini_pages, GeminiPageResult` stored as JSON; one entry appended per page processed by `ExtractPageWorker`

### New state
- `items_loading` added to `@statuses`: `~w(pending fetching extracting items_loading done failed)`
- The existing `validate_inclusion(:status, @statuses)` in `changeset/2` is kept in sync with this list. fsmx validates transitions independently (via the `transitions` map); the `validate_inclusion` guard in the general `changeset/2` is retained as a belt-and-suspenders guard for direct changeset usage outside of fsmx transitions.

### Type annotations (Elixir 1.19)

```elixir
@type status ::
  String.t()
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
  field :gallery_title,       :string         # original read-only Gemini output
  field :gallery_description, :string         # original read-only Gemini output
  field :next_page_url,       :string
  field :items_count,         :integer        # derived: length(raw_items) at build time
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

`items_count` is always computed as `length(raw_items)` when building the struct — it is never set independently from Gemini's response. This ensures consistency between the count and the actual stored items.

Stored in the `gemini_pages` JSON column on `sources`. `title` and `description` on `Source` are populated from the **first** page's `gallery_title` / `gallery_description` and remain independently editable via the UI.

---

## 6. items_loading → done Completion

`RenderWorker`, after marking an item as `ready`, checks whether it was the last item:

```elixir
# Correct fsmx multi pattern:
source = Catalog.get_source!(item.source_id)

if source.status == "items_loading" do
  pending_count = Catalog.count_items_not_terminal(source)

  if pending_count == 0 do
    multi =
      Ecto.Multi.new()
      |> Fsmx.transition_multi(source, :transition, "done", %{})

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      # Race: two RenderWorkers finish simultaneously and both see pending_count == 0.
      # The second attempt is rejected by fsmx because source is already "done" (or
      # "failed" if a concurrent worker failed and transitioned the source to failed).
      # In all cases, invalid_transition here is expected and safe — return :ok.
      {:error, :transition, :invalid_transition, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end
end
```

`count_items_not_terminal/1` queries `WHERE source_id = ? AND status NOT IN ('ready', 'failed')`. No counter cache. The last item to complete triggers the transition naturally. The race condition where two `RenderWorker` jobs concurrently see `pending_count == 0` is safe: fsmx rejects the second `items_loading → done` attempt as an invalid transition and the worker returns `:ok`.

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

The live integration test (Layer 2) is the iteration harness: run it after each stripper change to confirm Gemini still returns `is_gallery: true` and exactly 40 items.

---

## 8. Migration

One migration:
- Rename column `gallery_title` → `title` using `ALTER TABLE sources RENAME COLUMN` (supported in SQLite 3.25+; `ecto_sqlite3` uses SQLite ≥ 3.35, so this is safe)
- Rename column `gallery_description` → `description`
- Add column `gemini_pages` (text/JSON, not null, default `'[]'`)
- No schema change needed for `items_loading` — it is a string enum enforced at the application layer

---

## 9. Integration Test

File: `test/scientia_cognita/integration/source_lifecycle_test.exs`

### Layer 1 — Mocked (runs in CI)

Uses `hubble_page.html` as real HTML input through the real HTMLStripper. MockGemini returns a canned 40-item response; MockHttp returns the fixture HTML.

**Happy path (single page):**
1. `perform FetchPageWorker` → assert `source.status == "extracting"`, `raw_html` saved
2. `perform ExtractPageWorker` → assert:
   - `source.gemini_pages` has 1 entry
   - `hd(source.gemini_pages).items_count == 40`
   - `hd(source.gemini_pages).raw_items` has 40 entries
   - `source.title` / `source.description` populated from Gemini result
   - `source.status == "items_loading"`
   - 40 `DownloadImageWorker` jobs enqueued
3. For each of 40 items, perform `DownloadImageWorker`, `ProcessImageWorker`, `ColorAnalysisWorker`, `RenderWorker`
4. After last `RenderWorker`: assert all items `status == "ready"`, `source.status == "done"`

**Paginated source (2 pages):**
- First `ExtractPageWorker` run: status stays `"extracting"`, next page enqueued
- Assert `source.gemini_pages` has exactly 1 entry after first page
- Second `ExtractPageWorker` run: status → `"items_loading"`
- Assert `source.gemini_pages` has exactly 2 entries after second page

**Error paths:**
- `not_gallery` Gemini response → `source.status == "failed"`, descriptive error
- HTTP error during fetch → `source.status == "failed"`
- Gemini API error → `source.status == "failed"`
- Invalid transition attempted → gracefully ignored (`:ok` returned, no crash)

**Mid-pagination `not_gallery`:**
- If page 1 succeeds but page 2 returns `is_gallery: false`, the source transitions to `"failed"` with a descriptive error. Items already created from page 1 remain in the DB but their source is failed.

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
| `lib/.../catalog/source.ex` | Add fsmx + transitions map, rename fields, add embeds_many, typed struct, `items_loading` state |
| `lib/.../catalog/item.ex` | Add fsmx + transitions map, typed struct, all transition_changeset callbacks |
| `lib/.../catalog/gemini_page_result.ex` | **New** — embedded schema with typed struct |
| `lib/.../source_fsm.ex` | **Delete** |
| `lib/.../item_fsm.ex` | **Delete** |
| `lib/.../html_stripper.ex` | Body-only, drop class/id, add data-src, remove svg + descendants, remove comments, lower max_bytes |
| `lib/.../workers/fetch_page_worker.ex` | Use `Ecto.Multi` + `Fsmx.transition_multi` |
| `lib/.../workers/extract_page_worker.ex` | Use `Fsmx.transition_multi`, build + append `GeminiPageResult` |
| `lib/.../catalog.ex` | Add `count_items_not_terminal/1` — queries `WHERE source_id = ? AND status NOT IN ('ready', 'failed')` |
| `lib/.../workers/render_worker.ex` | After item→ready, check source completion and transition to done |
| `priv/repo/migrations/YYYYMMDD_formal_fsm.exs` | **New** — rename columns, add gemini_pages column |
| `test/.../integration/source_lifecycle_test.exs` | **New** — full pipeline integration test (Layer 1 + Layer 2) |
| `test/.../source_fsm_test.exs` | **Delete** (replaced by schema-level transition tests) |
| `test/.../item_fsm_test.exs` | **Delete** (replaced by schema-level transition tests) |
| `test/support/fixtures/catalog_fixtures.ex` | Update fixtures for renamed fields (`title`, `description`) |
