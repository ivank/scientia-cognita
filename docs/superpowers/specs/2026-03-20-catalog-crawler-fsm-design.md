# Catalog Crawler FSM Design

**Date:** 2026-03-20
**Status:** Approved

## Overview

Refactor the catalog crawling pipeline from monolithic Oban workers into two explicit finite state machines (FSMs): one for the source (gallery-level crawl) and one for each item (image pipeline). The FSM logic lives in pure validator modules (`SourceFSM`, `ItemFSM`); Oban workers remain responsible for async execution.

The key architectural change from the current implementation: Gemini generates CSS selectors **once** from the first page and stores them on the source record. Subsequent pages are scraped programmatically using Floki + those selectors — Gemini is not called per page.

---

## State Machines

### Source FSM

Represents the lifecycle of crawling a single gallery source.

```
pending
  │ :start
  ▼
fetching          ← Req.get(url), save raw_html to source record
  │ :fetched
  ▼
analyzing         ← strip HTML, call Gemini for: classification, title,
  │                  description, CSS selectors (title/image/description/
  │                  copyright/next_page); store results on source
  │ :analyzed (is_gallery=true)          │ :not_gallery / :failed
  ▼                                      ▼
extracting        ← use stored CSS selectors + Floki to extract items       failed
  │ :page_done (next_page_url present)
  ├──────────────────────────────────────┐ (self-loop: enqueue next page)
  │ :page_done (next_page_url absent)
  ▼
done
```

Valid transitions:

| From        | Event         | To           |
|-------------|---------------|--------------|
| pending     | :start        | fetching     |
| fetching    | :fetched      | analyzing    |
| analyzing   | :analyzed     | extracting   |
| analyzing   | :not_gallery  | failed       |
| extracting  | :page_done    | extracting   |
| extracting  | :exhausted    | done         |
| any         | :failed       | failed       |

### Item FSM

Represents the lifecycle of processing a single gallery image.

```
pending
  │ :start
  ▼
downloading     ← fetch original_url, upload original to MinIO
  │ :downloaded
  ▼
processing      ← resize/crop to 16:9 FHD (1920×1080), upload processed image
  │ :processed
  ▼
color_analysis  ← generate 200px thumbnail, call Gemini for text/bg colors,
  │                store text_color / bg_color / bg_opacity on item
  │ :colors_ready
  ▼
render          ← read processed image + stored colors, render text overlay,
  │                upload final image
  │ :rendered
  ▼
ready

Any state → :failed → failed
```

Valid transitions:

| From           | Event          | To             |
|----------------|----------------|----------------|
| pending        | :start         | downloading    |
| downloading    | :downloaded    | processing     |
| processing     | :processed     | color_analysis |
| color_analysis | :colors_ready  | render         |
| render         | :rendered      | ready          |
| any            | :failed        | failed         |

---

## Database Changes

### Sources table — new columns

| Column               | Type            | Notes                                        |
|----------------------|-----------------|----------------------------------------------|
| `raw_html`           | text, nullable  | Set in `fetching`, kept permanently          |
| `gallery_title`      | string, nullable| Gemini-extracted title for the gallery       |
| `gallery_description`| string, nullable| Gemini-extracted description                 |
| `selector_title`     | string, nullable| CSS selector for item title                  |
| `selector_image`     | string, nullable| CSS selector for item image URL              |
| `selector_description`| string, nullable| CSS selector for item description           |
| `selector_copyright` | string, nullable| CSS selector for item copyright              |
| `selector_next_page` | string, nullable| CSS selector for next-page link              |

**Source statuses** (replaces `running`):
`pending → fetching → analyzing → extracting → done / failed`

### Items table — new columns

| Column       | Type            | Notes                                          |
|--------------|-----------------|------------------------------------------------|
| `text_color` | string, nullable| Stored by `color_analysis` worker              |
| `bg_color`   | string, nullable| Stored by `color_analysis` worker              |
| `bg_opacity` | float, nullable | Stored by `color_analysis` worker              |

**Item statuses** (inserts two new states after `processing`):
`pending → downloading → processing → color_analysis → render → ready / failed`

---

## FSM Modules

Two pure modules. No side effects, no Oban calls, no DB access.

### `ScientiaCognita.SourceFSM`

```elixir
def transition(%Source{status: "pending"},    :start),       do: {:ok, "fetching"}
def transition(%Source{status: "fetching"},   :fetched),     do: {:ok, "analyzing"}
def transition(%Source{status: "analyzing"},  :analyzed),    do: {:ok, "extracting"}
def transition(%Source{status: "analyzing"},  :not_gallery), do: {:ok, "failed"}
def transition(%Source{status: "extracting"}, :page_done),   do: {:ok, "extracting"}
def transition(%Source{status: "extracting"}, :exhausted),   do: {:ok, "done"}
def transition(%Source{status: _},            :failed),      do: {:ok, "failed"}
def transition(_, _),                                        do: {:error, :invalid_transition}
```

### `ScientiaCognita.ItemFSM`

```elixir
def transition(%Item{status: "pending"},        :start),        do: {:ok, "downloading"}
def transition(%Item{status: "downloading"},    :downloaded),   do: {:ok, "processing"}
def transition(%Item{status: "processing"},     :processed),    do: {:ok, "color_analysis"}
def transition(%Item{status: "color_analysis"}, :colors_ready), do: {:ok, "render"}
def transition(%Item{status: "render"},         :rendered),     do: {:ok, "ready"}
def transition(%Item{status: _},                :failed),       do: {:ok, "failed"}
def transition(_, _),                                           do: {:error, :invalid_transition}
```

Workers use the FSM before any DB update:

```elixir
with {:ok, next_status} <- SourceFSM.transition(source, :fetched),
     {:ok, source} <- Catalog.update_source_status(source, next_status) do
  # enqueue next worker
end
```

---

## Worker Structure

### Source pipeline (replaces `CrawlPageWorker`)

| Worker               | Queue    | FSM transition            | Responsibility                                                                 |
|----------------------|----------|---------------------------|--------------------------------------------------------------------------------|
| `FetchPageWorker`    | `:fetch` | `pending→fetching→analyzing` | `Req.get(url)`, save `raw_html` on source, enqueue `AnalyzePageWorker`      |
| `AnalyzePageWorker`  | `:fetch` | `analyzing→extracting` or `→failed` | Strip HTML via `HTMLStripper`, call Gemini for classification + selectors + title/description, store on source, enqueue `ExtractPageWorker` |
| `ExtractPageWorker`  | `:fetch` | `extracting→extracting` or `→done` | Use Floki + stored CSS selectors to extract items from `url` arg, create Item records, enqueue item workers, follow `next_page_url` |

### Item pipeline (replaces `DownloadImageWorker` + `ProcessImageWorker`)

| Worker                 | Queue      | FSM transition                   | Responsibility                                                        |
|------------------------|------------|----------------------------------|-----------------------------------------------------------------------|
| `DownloadImageWorker`  | `:fetch`   | `pending→downloading→processing` | Fetch `original_url`, upload to MinIO, enqueue `ProcessImageWorker`  |
| `ProcessImageWorker`   | `:process` | `processing→color_analysis`      | Resize/crop to 1920×1080, upload processed image, enqueue `ColorAnalysisWorker` |
| `ColorAnalysisWorker`  | `:process` | `color_analysis→render`          | Generate 200px thumbnail, call Gemini for colors, store `text_color`/`bg_color`/`bg_opacity`, enqueue `RenderWorker` |
| `RenderWorker`         | `:process` | `render→ready`                   | Read processed image + stored colors, render text overlay, upload final image |

---

## Testing Approach (red-green-refactor)

### FSM modules — pure unit tests

- All valid transitions return `{:ok, next_state}`
- All invalid transitions return `{:error, :invalid_transition}`
- The `:failed` catch-all fires from every non-terminal state

### Workers — isolated tests with mocks

- `Req` and `Gemini` calls mocked via `Mox` (define `GeminiBehaviour` / `HttpBehaviour`)
- Happy path: correct FSM transition + correct DB state after worker runs
- Failure path: error stored on record, Oban returns `{:error, reason}` for retry

### CSS extraction (`ExtractPageWorker`)

- Fixture HTML files in `test/fixtures/` representing known gallery structures
- Assert correct items extracted given pre-set selectors on the source
- Assert `next_page_url` correctly followed or nil when exhausted

### Integration

- Source pipeline: `FetchPageWorker → AnalyzePageWorker → ExtractPageWorker` with mocked HTTP + Gemini
- Item pipeline: `DownloadImageWorker → ProcessImageWorker → ColorAnalysisWorker → RenderWorker` with mocked HTTP + Storage

Each cycle: write failing test (red) → implement (green) → simplify (refactor).

---

## Files Affected

**New:**
- `lib/scientia_cognita/source_fsm.ex`
- `lib/scientia_cognita/item_fsm.ex`
- `lib/scientia_cognita/workers/fetch_page_worker.ex`
- `lib/scientia_cognita/workers/analyze_page_worker.ex`
- `lib/scientia_cognita/workers/extract_page_worker.ex`
- `lib/scientia_cognita/workers/color_analysis_worker.ex`
- `lib/scientia_cognita/workers/render_worker.ex`
- `priv/repo/migrations/*_add_fsm_fields_to_sources.exs`
- `priv/repo/migrations/*_add_fsm_fields_to_items.exs`

**Modified:**
- `lib/scientia_cognita/catalog/source.ex` — new statuses + fields
- `lib/scientia_cognita/catalog/item.ex` — new statuses + fields
- `lib/scientia_cognita/workers/process_image_worker.ex` — split into `ProcessImageWorker` + `ColorAnalysisWorker` + `RenderWorker`

**Deleted:**
- `lib/scientia_cognita/workers/crawl_page_worker.ex`
- `lib/scientia_cognita/workers/download_image_worker.ex` — replaced by new version
