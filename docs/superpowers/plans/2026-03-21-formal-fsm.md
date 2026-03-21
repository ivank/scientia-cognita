# Formal FSM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hand-rolled SourceFSM/ItemFSM pattern-match modules with fsmx, making state transitions atomic with their data writes, enforced by typed `transition_changeset/4` callbacks on each schema.

**Architecture:** `Source` and `Item` schemas each `use Fsmx.Ecto` with a `transitions` map and `transition_changeset/4` callbacks. Workers build an `Ecto.Multi`, pipe it through `Fsmx.transition_multi/5`, then call `Repo.transaction/1` — validated transition + field writes happen atomically. A new `GeminiPageResult` embedded schema appends the full Gemini extraction output per page. `RenderWorker` checks item completion and closes the `items_loading → done` transition on `Source`.

**Tech Stack:** Elixir 1.19.5, fsmx ~> 0.4, Ecto/SQLite (ecto_sqlite3), Oban, Mox, Floki

**Spec:** `docs/superpowers/specs/2026-03-21-formal-fsm-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `mix.exs` | Modify | Add fsmx dep |
| `lib/.../catalog/gemini_page_result.ex` | Create | Embedded schema + `new/1` constructor |
| `lib/.../catalog/source.ex` | Rewrite | fsmx, typed struct, embeds_many, renamed fields, remove old changesets |
| `lib/.../catalog/item.ex` | Rewrite | fsmx, typed struct, transition_changeset callbacks |
| `lib/.../catalog.ex` | Modify | Remove obsolete Source update fns; add `count_items_not_terminal/1`; add `reset_source/1` |
| `lib/.../live/console/source_show_live.ex` | Modify | `restart_source` handler: replace two-call pattern with `Catalog.reset_source/1` |
| `lib/.../html_stripper.ex` | Rewrite | Body-only, drop class/id, data-src, remove svg, remove comments, 80KB cap |
| `lib/.../source_fsm.ex` | Delete | Replaced by fsmx |
| `lib/.../item_fsm.ex` | Delete | Replaced by fsmx |
| `lib/.../workers/fetch_page_worker.ex` | Rewrite | Use `fsm_transition/3` helper |
| `lib/.../workers/extract_page_worker.ex` | Rewrite | Use `fsm_transition/3`, build `GeminiPageResult` |
| `lib/.../workers/download_image_worker.ex` | Rewrite | Use `fsm_transition/3` |
| `lib/.../workers/process_image_worker.ex` | Rewrite | Use `fsm_transition/3` |
| `lib/.../workers/color_analysis_worker.ex` | Rewrite | Use `fsm_transition/3` |
| `lib/.../workers/render_worker.ex` | Rewrite | Use `fsm_transition/3` + `maybe_complete_source/1` |
| `priv/repo/migrations/20260321000000_formal_fsm.exs` | Create | Rename columns, add gemini_pages |
| `test/support/fixtures/catalog_fixtures.ex` | Modify | Rename `gallery_title`→`title`, `gallery_description`→`description` |
| `test/.../catalog/gemini_page_result_test.exs` | Create | Unit tests for `new/1` and `changeset/2` |
| `test/.../html_stripper_test.exs` | Create | Attribute + element removal + Hubble size test |
| `test/.../source_fsm_test.exs` | Delete | Replaced by fsmx schema-level tests |
| `test/.../item_fsm_test.exs` | Delete | Replaced by fsmx schema-level tests |
| `test/.../integration/source_lifecycle_test.exs` | Create | Full pipeline: mocked (Layer 1) + live Gemini (Layer 2) |

---

## Shared Private Helper (used in every rewritten worker)

Every worker gets this private function — do not extract to a shared module yet:

```elixir
defp fsm_transition(schema, new_state, params \\ %{}) do
  Ecto.Multi.new()
  |> Fsmx.transition_multi(schema, :transition, new_state, params)
  |> Repo.transaction()
  |> case do
    {:ok, %{transition: updated}} -> {:ok, updated}
    {:error, :transition, :invalid_transition, _} -> {:error, :invalid_transition}
    {:error, _, reason, _} -> {:error, reason}
  end
end
```

Workers must alias `ScientiaCognita.Repo` and remove their `alias ScientiaCognita.{SourceFSM}` / `alias ScientiaCognita.{ItemFSM}` aliases.

---

## Task 1: Add fsmx dependency

**Files:**
- Modify: `mix.exs`

- [ ] **Add fsmx to deps**

In `mix.exs`, inside `defp deps do`, add after the `{:mox, ...}` line:
```elixir
{:fsmx, "~> 0.4"}
```

- [ ] **Fetch and compile**

```bash
mix deps.get
mix compile
```

Expected: no errors. fsmx should appear in `mix.lock`.

- [ ] **Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add fsmx for Ecto-integrated state machine"
```

---

## Task 2: GeminiPageResult embedded schema

**Files:**
- Create: `lib/scientia_cognita/catalog/gemini_page_result.ex`
- Create: `test/scientia_cognita/catalog/gemini_page_result_test.exs`

- [ ] **Write the failing tests**

```elixir
# test/scientia_cognita/catalog/gemini_page_result_test.exs
defmodule ScientiaCognita.Catalog.GeminiPageResultTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.Catalog.GeminiPageResult

  describe "new/1" do
    test "derives items_count from length of raw_items" do
      result = GeminiPageResult.new(%{
        page_url: "https://example.com/gallery",
        is_gallery: true,
        gallery_title: "Test Gallery",
        gallery_description: "A test gallery",
        next_page_url: nil,
        raw_items: [%{"image_url" => "https://example.com/1.jpg"}]
      })

      assert result.items_count == 1
      assert result.page_url == "https://example.com/gallery"
      assert result.is_gallery == true
      assert result.gallery_title == "Test Gallery"
      assert result.raw_items == [%{"image_url" => "https://example.com/1.jpg"}]
    end

    test "items_count is 0 for empty raw_items" do
      result = GeminiPageResult.new(%{
        page_url: "https://example.com",
        is_gallery: false,
        gallery_title: nil,
        gallery_description: nil,
        next_page_url: nil,
        raw_items: []
      })

      assert result.items_count == 0
    end

    test "sets generated_at to current UTC second" do
      before = DateTime.utc_now(:second)
      result = GeminiPageResult.new(%{page_url: "x", is_gallery: false,
        gallery_title: nil, gallery_description: nil, next_page_url: nil, raw_items: []})
      after_t = DateTime.utc_now(:second)

      assert DateTime.compare(result.generated_at, before) in [:gt, :eq]
      assert DateTime.compare(result.generated_at, after_t) in [:lt, :eq]
    end
  end

  describe "changeset/2" do
    test "casts all fields successfully" do
      attrs = %{
        page_url: "https://example.com",
        is_gallery: true,
        gallery_title: "Test",
        gallery_description: "Desc",
        next_page_url: nil,
        items_count: 5,
        raw_items: [%{"image_url" => "https://example.com/1.jpg"}],
        generated_at: DateTime.utc_now(:second)
      }

      cs = GeminiPageResult.changeset(%GeminiPageResult{}, attrs)
      assert cs.valid?
    end
  end
end
```

- [ ] **Run test to verify it fails**

```bash
mix test test/scientia_cognita/catalog/gemini_page_result_test.exs
```

Expected: compile error — `GeminiPageResult` does not exist.

- [ ] **Implement GeminiPageResult**

```elixir
# lib/scientia_cognita/catalog/gemini_page_result.ex
defmodule ScientiaCognita.Catalog.GeminiPageResult do
  @moduledoc """
  Embedded schema that captures the full Gemini extraction output for one page.
  One entry is appended to `Source.gemini_pages` per ExtractPageWorker run.
  `items_count` is always derived from `length(raw_items)` — never set independently.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :page_url,            :string
    field :is_gallery,          :boolean
    field :gallery_title,       :string
    field :gallery_description, :string
    field :next_page_url,       :string
    field :items_count,         :integer
    field :raw_items,           {:array, :map}
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

  @spec new(map()) :: t()
  def new(attrs) do
    raw_items = attrs[:raw_items] || []
    %__MODULE__{
      page_url:            attrs[:page_url],
      is_gallery:          attrs[:is_gallery],
      gallery_title:       attrs[:gallery_title],
      gallery_description: attrs[:gallery_description],
      next_page_url:       attrs[:next_page_url],
      raw_items:           raw_items,
      items_count:         length(raw_items),
      generated_at:        DateTime.utc_now(:second)
    }
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:page_url, :is_gallery, :gallery_title, :gallery_description,
                    :next_page_url, :items_count, :raw_items, :generated_at])
  end
end
```

- [ ] **Run test to verify it passes**

```bash
mix test test/scientia_cognita/catalog/gemini_page_result_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/catalog/gemini_page_result.ex \
        test/scientia_cognita/catalog/gemini_page_result_test.exs
git commit -m "feat: add GeminiPageResult embedded schema"
```

---

## Task 3: Database migration

**Files:**
- Create: `priv/repo/migrations/20260321000000_formal_fsm.exs`

- [ ] **Create migration**

```elixir
# priv/repo/migrations/20260321000000_formal_fsm.exs
defmodule ScientiaCognita.Repo.Migrations.FormalFsm do
  use Ecto.Migration

  def change do
    # SQLite >= 3.25 supports RENAME COLUMN; ecto_sqlite3 ships SQLite >= 3.35
    rename table(:sources), :gallery_title, to: :title
    rename table(:sources), :gallery_description, to: :description

    alter table(:sources) do
      add :gemini_pages, :text, default: "[]", null: false
    end
  end
end
```

- [ ] **Run migration**

```bash
mix ecto.migrate
```

Expected: `[info] == Running 20260321000000 ScientiaCognita.Repo.Migrations.FormalFsm.change/0 forward`

- [ ] **Verify test DB migrates**

```bash
mix test --only nonexistent 2>&1 | head -5
```

Expected: no migration errors.

- [ ] **Commit**

```bash
git add priv/repo/migrations/20260321000000_formal_fsm.exs
git commit -m "feat: migration — rename gallery fields, add gemini_pages column"
```

---

## Task 4: Rewrite Source schema

**Files:**
- Modify: `lib/scientia_cognita/catalog/source.ex`

- [ ] **Rewrite source.ex**

Replace the entire file:

```elixir
defmodule ScientiaCognita.Catalog.Source do
  @moduledoc """
  Source schema with fsmx state machine.

  State transitions:
    pending → fetching → extracting → items_loading → done
    any non-terminal → failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ScientiaCognita.Catalog.{GeminiPageResult, Item}

  use Fsmx.Ecto,
    transitions: %{
      "pending"       => ["fetching", "failed"],
      "fetching"      => ["extracting", "failed"],
      "extracting"    => ["extracting", "items_loading", "failed"],
      "items_loading" => ["done", "failed"]
    }

  @statuses ~w(pending fetching extracting items_loading done failed)

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

  schema "sources" do
    field :url,           :string
    field :name,          :string
    field :status,        :string, default: "pending"
    field :next_page_url, :string
    field :pages_fetched, :integer, default: 0
    field :total_items,   :integer, default: 0
    field :error,         :string
    field :raw_html,      :string
    field :title,         :string
    field :description,   :string

    embeds_many :gemini_pages, GeminiPageResult

    has_many :items, Item

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:url, :name, :status, :next_page_url, :pages_fetched,
                    :total_items, :error, :title, :description])
    |> validate_required([:url, :name])
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint(:url)
  end

  @doc "Used by Catalog.update_source_status/3 for fixture/test setup only."
  def status_changeset(source, status, opts \\ []) do
    source
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  # ---------------------------------------------------------------------------
  # fsmx transition_changeset callbacks
  # ---------------------------------------------------------------------------

  def transition_changeset(changeset, "pending", "fetching", _params), do: changeset

  def transition_changeset(changeset, "fetching", "extracting", params) do
    changeset
    |> cast(params, [:raw_html])
    |> validate_required([:raw_html])
  end

  def transition_changeset(changeset, "extracting", "extracting", params) do
    existing = get_field(changeset, :gemini_pages) || []
    changeset
    |> cast(params, [:pages_fetched, :total_items, :next_page_url])
    |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
  end

  def transition_changeset(changeset, "extracting", "items_loading", params) do
    existing = get_field(changeset, :gemini_pages) || []
    changeset
    |> cast(params, [:pages_fetched, :total_items, :title, :description])
    |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
  end

  def transition_changeset(changeset, "items_loading", "done", _params), do: changeset

  def transition_changeset(changeset, _old, "failed", params) do
    changeset
    |> cast(params, [:error])
    |> validate_required([:error])
  end
end
```

- [ ] **Run full test suite to find what broke**

```bash
mix test 2>&1 | tail -30
```

Expect failures in: `source_test.exs`, `fetch_page_worker_test.exs`, `extract_page_worker_test.exs`, `source_fsm_test.exs`. These are expected and will be fixed in subsequent tasks.

- [ ] **Rewrite source_test.exs**

The existing `source_test.exs` has two describe blocks (`html_changeset/2` and `analyze_changeset/2`) that call functions removed from Source. These blocks must be **deleted in their entirety** — the functions no longer exist and the tests will not compile. Replace them with `transition_changeset` tests, and update the `status_changeset/3` block to include `items_loading`:

```elixir
defmodule ScientiaCognita.Catalog.SourceTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.{Source, GeminiPageResult}

  describe "status_changeset/3" do
    test "accepts all FSM statuses including items_loading" do
      for status <- ~w(pending fetching extracting items_loading done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects unknown status" do
      cs = Source.status_changeset(%Source{status: "pending"}, "analyzing")
      refute cs.valid?
    end
  end

  describe "transition_changeset/4 — fetching → extracting" do
    test "requires raw_html" do
      cs = Source.transition_changeset(
        Ecto.Changeset.change(%Source{status: "fetching"}),
        "fetching", "extracting", %{}
      )
      refute cs.valid?
      assert {:raw_html, {"can't be blank", _}} = hd(cs.errors)
    end

    test "accepts raw_html" do
      cs = Source.transition_changeset(
        Ecto.Changeset.change(%Source{status: "fetching"}),
        "fetching", "extracting", %{raw_html: "<html>ok</html>"}
      )
      assert cs.valid?
    end
  end

  describe "transition_changeset/4 — failed" do
    test "requires error message" do
      cs = Source.transition_changeset(
        Ecto.Changeset.change(%Source{status: "extracting"}),
        "extracting", "failed", %{}
      )
      refute cs.valid?
    end

    test "accepts error message" do
      cs = Source.transition_changeset(
        Ecto.Changeset.change(%Source{status: "extracting"}),
        "extracting", "failed", %{error: "Something went wrong"}
      )
      assert cs.valid?
    end
  end

  describe "transition_changeset/4 — extracting → items_loading" do
    test "appends gemini_page to gemini_pages" do
      page = GeminiPageResult.new(%{
        page_url: "https://example.com", is_gallery: true,
        gallery_title: "Test", gallery_description: "Desc",
        next_page_url: nil, raw_items: []
      })

      cs = Source.transition_changeset(
        Ecto.Changeset.change(%Source{status: "extracting", gemini_pages: []}),
        "extracting", "items_loading",
        %{pages_fetched: 1, total_items: 0, title: "Test", description: "Desc", gemini_page: page}
      )

      assert cs.valid?
      assert length(Ecto.Changeset.get_change(cs, :gemini_pages)) == 1
    end
  end
end
```

- [ ] **Run source_test.exs only**

```bash
mix test test/scientia_cognita/catalog/source_test.exs
```

Expected: passes.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/catalog/source.ex test/scientia_cognita/catalog/source_test.exs
git commit -m "feat: rewrite Source schema with fsmx and typed struct"
```

---

## Task 5: Update Catalog context and fixtures

**Files:**
- Modify: `lib/scientia_cognita/catalog.ex`
- Modify: `test/support/fixtures/catalog_fixtures.ex`

- [ ] **Remove obsolete Source update functions from catalog.ex**

Delete these three functions (workers will use fsmx directly; they no longer call these):

```elixir
# DELETE:
def update_source_html/2        # was: Source.html_changeset — removed from Source
def update_source_analysis/2    # was: Source.analyze_changeset — removed from Source
def update_source_progress/2    # was: Source.progress_changeset — removed from Source
```

⚠️ `source_show_live.ex` calls `Catalog.update_source_progress/2` in its `restart_source` handler — fix it in the same commit (see step below) to avoid a broken compile window.

- [ ] **Add count_items_not_terminal/1 and reset_source/1 to catalog.ex**

In the Sources section, add after `delete_source_with_storage/1`:

```elixir
@doc """
Resets a source to pending for re-processing. Called by SourceShowLive restart.
Clears progress counters, pagination state, and error atomically.
"""
def reset_source(%Source{} = source) do
  source
  |> Ecto.Changeset.change(
    status: "pending",
    pages_fetched: 0,
    total_items: 0,
    next_page_url: nil,
    error: nil
  )
  |> Repo.update()
end
```

In the Items section, add after `count_items_by_status/1`:

```elixir
@doc """
Returns the count of items for `source` that are not yet in a terminal state.
Terminal states are "ready" and "failed". Used by RenderWorker to detect
when all items have completed and the source can transition to "done".
"""
def count_items_not_terminal(%Source{id: source_id}) do
  Repo.aggregate(
    from(i in Item,
      where: i.source_id == ^source_id and i.status not in ["ready", "failed"]),
    :count
  )
end
```

- [ ] **Update SourceShowLive restart_source handler**

In `lib/scientia_cognita_web/live/console/source_show_live.ex`, replace the `restart_source` handler (currently two calls) with the new single-call approach:

```elixir
# BEFORE (lines 218-219):
{:ok, source} = Catalog.update_source_status(source, "pending", error: nil)
Catalog.update_source_progress(source, %{pages_fetched: 0, total_items: 0, next_page_url: nil})

# AFTER:
{:ok, source} = Catalog.reset_source(source)
```

The rest of the handler (Oban.insert for FetchPageWorker, assign, etc.) stays unchanged.

- [ ] **Update CatalogFixtures for renamed fields**

In `test/support/fixtures/catalog_fixtures.ex`, the `source_fixture/1` function uses `Catalog.update_source_html`. Since that function is removed, update any fixture logic that references it. Also update any field reference from `gallery_title`/`gallery_description` to `title`/`description`.

The fixture currently pops `:raw_html` and calls `Catalog.update_source_html`. Since that function is removed, replace with a direct changeset update:

```elixir
source =
  if raw_html do
    {:ok, source} =
      source
      |> Ecto.Changeset.change(raw_html: raw_html)
      |> ScientiaCognita.Repo.update()
    source
  else
    source
  end
```

- [ ] **Run full test suite**

```bash
mix test 2>&1 | tail -30
```

Remaining failures should now be only in FSM tests and worker tests. `catalog_test.exs`, `source_test.exs`, and fixture-dependent tests should pass.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/catalog.ex \
        lib/scientia_cognita_web/live/console/source_show_live.ex \
        test/support/fixtures/catalog_fixtures.ex
git commit -m "feat: remove obsolete Source update fns, add reset_source/1, count_items_not_terminal"
```

---

## Task 6: Rewrite Item schema

**Files:**
- Modify: `lib/scientia_cognita/catalog/item.ex`

- [ ] **Rewrite item.ex**

Replace the entire file:

```elixir
defmodule ScientiaCognita.Catalog.Item do
  @moduledoc """
  Item schema with fsmx state machine.

  State transitions:
    pending → downloading → processing → color_analysis → render → ready
    any non-terminal → failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ScientiaCognita.Catalog.{Source, Catalog, CatalogItem}

  use Fsmx.Ecto,
    transitions: %{
      "pending"        => ["downloading", "failed"],
      "downloading"    => ["processing", "failed"],
      "processing"     => ["color_analysis", "failed"],
      "color_analysis" => ["render", "failed"],
      "render"         => ["ready", "failed"]
    }

  @statuses ~w(pending downloading processing color_analysis render ready failed)

  @type status :: String.t()
  # valid values: "pending" | "downloading" | "processing" |
  #               "color_analysis" | "render" | "ready" | "failed"

  @type t :: %__MODULE__{
    id:            integer() | nil,
    title:         String.t(),
    description:   String.t() | nil,
    author:        String.t() | nil,
    copyright:     String.t() | nil,
    original_url:  String.t() | nil,
    storage_key:   String.t() | nil,
    processed_key: String.t() | nil,
    status:        status(),
    error:         String.t() | nil,
    text_color:    String.t() | nil,
    bg_color:      String.t() | nil,
    bg_opacity:    float() | nil,
    source_id:     integer() | nil,
    source:        Source.t() | Ecto.Association.NotLoaded.t(),
    catalogs:      [Catalog.t()] | Ecto.Association.NotLoaded.t(),
    inserted_at:   DateTime.t() | nil,
    updated_at:    DateTime.t() | nil
  }

  schema "items" do
    field :title,         :string
    field :description,   :string
    field :author,        :string
    field :copyright,     :string
    field :original_url,  :string
    field :storage_key,   :string
    field :processed_key, :string
    field :status,        :string, default: "pending"
    field :error,         :string

    # Set during color_analysis
    field :text_color,  :string
    field :bg_color,    :string
    field :bg_opacity,  :float

    belongs_to :source, Source
    many_to_many :catalogs, Catalog, join_through: CatalogItem

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :description, :author, :copyright, :original_url, :source_id])
    |> validate_required([:title, :source_id])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:source)
  end

  @doc "Used by Catalog.update_item_status/3 for fixture/test setup only."
  def status_changeset(item, status, opts \\ []) do
    item
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Used by Catalog.update_item_storage/2 for fixture setup."
  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:storage_key, :processed_key])
  end

  @doc "Used by Catalog.update_item_colors/2 for fixture setup."
  def color_changeset(item, attrs) do
    item
    |> cast(attrs, [:text_color, :bg_color, :bg_opacity])
    |> validate_required([:text_color, :bg_color, :bg_opacity])
  end

  # ---------------------------------------------------------------------------
  # fsmx transition_changeset callbacks
  # ---------------------------------------------------------------------------

  def transition_changeset(changeset, "pending", "downloading", _params), do: changeset

  def transition_changeset(changeset, "downloading", "processing", params) do
    changeset
    |> cast(params, [:storage_key])
    |> validate_required([:storage_key])
  end

  def transition_changeset(changeset, "processing", "color_analysis", params) do
    changeset
    |> cast(params, [:processed_key])
    |> validate_required([:processed_key])
  end

  def transition_changeset(changeset, "color_analysis", "render", params) do
    changeset
    |> cast(params, [:text_color, :bg_color, :bg_opacity])
    |> validate_required([:text_color, :bg_color, :bg_opacity])
  end

  # NOTE: spec says "no extra fields required" but we intentionally cast processed_key
  # here so RenderWorker can write the final rendered image path atomically in
  # the render→ready transition, eliminating a separate update_item_storage call.
  def transition_changeset(changeset, "render", "ready", params) do
    cast(changeset, params, [:processed_key])
  end

  def transition_changeset(changeset, _old, "failed", params) do
    changeset
    |> cast(params, [:error])
    |> validate_required([:error])
  end
end
```

- [ ] **Run item_test.exs**

```bash
mix test test/scientia_cognita/catalog/item_test.exs
```

Expected: passes (item schema tests don't depend on FSM modules).

- [ ] **Commit**

```bash
git add lib/scientia_cognita/catalog/item.ex
git commit -m "feat: rewrite Item schema with fsmx and typed struct"
```

---

## Task 7: Improve HTMLStripper

**Files:**
- Create: `test/scientia_cognita/html_stripper_test.exs`
- Modify: `lib/scientia_cognita/html_stripper.ex`

- [ ] **Write failing tests**

```elixir
# test/scientia_cognita/html_stripper_test.exs
defmodule ScientiaCognita.HTMLStripperTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.HTMLStripper

  @hubble_html File.read!("test/fixtures/hubble_page.html")

  describe "attribute filtering" do
    test "removes class attributes from all elements" do
      html = ~s(<div class="gallery"><p class="caption">Text</p></div>)
      result = HTMLStripper.strip(html)
      refute result =~ ~r/class=/
    end

    test "removes id attributes from all elements" do
      html = ~s(<div id="main"><p id="text">Content</p></div>)
      result = HTMLStripper.strip(html)
      refute result =~ ~r/id=/
    end

    test "preserves href on anchors" do
      html = ~s(<body><a href="https://example.com" class="link">Click</a></body>)
      result = HTMLStripper.strip(html)
      assert result =~ ~s(href="https://example.com")
      refute result =~ ~r/class=/
    end

    test "preserves src, alt, srcset on images" do
      html = ~s(<body><img src="https://example.com/img.jpg" alt="Test" srcset="img 2x" class="photo"></body>)
      result = HTMLStripper.strip(html)
      assert result =~ ~s(src="https://example.com/img.jpg")
      assert result =~ ~s(alt="Test")
      assert result =~ "srcset="
      refute result =~ ~r/class=/
    end

    test "preserves data-src and data-srcset on images (lazy loading)" do
      html = ~s(<body><img data-src="https://example.com/lazy.jpg" data-srcset="https://example.com/lazy@2x.jpg 2x"></body>)
      result = HTMLStripper.strip(html)
      assert result =~ "data-src="
      assert result =~ "data-srcset="
    end
  end

  describe "element removal" do
    test "removes script tags" do
      html = "<html><body><script>alert('x')</script><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<script"
      assert result =~ "Content"
    end

    test "removes svg elements and all descendants" do
      html = "<html><body><svg><path d='M 0 0'/><use href='#icon'/></svg><p>After</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<svg"
      refute result =~ "<path"
      refute result =~ "<use"
      assert result =~ "After"
    end

    test "removes HTML comments" do
      html = "<html><body><!-- This is a comment --><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<!--"
      assert result =~ "Content"
    end

    test "removes head content, keeps body" do
      html = "<html><head><title>Page</title><meta charset='utf-8'><link rel='stylesheet'></head><body><p>Body</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<title>"
      refute result =~ "<meta"
      refute result =~ "<link"
      assert result =~ "Body"
    end
  end

  describe "Hubble fixture" do
    test "strips hubble_page.html to under 100KB" do
      result = HTMLStripper.strip(@hubble_html)
      assert byte_size(result) < 100_000,
             "Expected stripped HTML < 100KB, got #{byte_size(result)} bytes"
    end
  end
end
```

- [ ] **Run tests to verify they fail**

```bash
mix test test/scientia_cognita/html_stripper_test.exs
```

Expected: several failures (class/id removal, svg, comments, head removal, Hubble size).

- [ ] **Rewrite html_stripper.ex**

```elixir
defmodule ScientiaCognita.HTMLStripper do
  @moduledoc """
  Strips an HTML document down to clean semantic content suitable for
  passing to an LLM (Gemini) for structured data extraction.

  Removes: <head>, scripts, styles, SVG and all descendants, nav, header,
  footer, ads, aria-hidden elements, HTML comments, all class/id attributes.
  Keeps: href on <a>; src/srcset/alt/data-src/data-srcset on <img>/<figure>/<source>.
  """

  @remove_selectors ~w(
    script style noscript iframe
    nav header footer aside
    [role=navigation] [role=banner] [role=contentinfo]
    .nav .navbar .menu .sidebar .footer .header .ad .ads .advertisement
    form button input select textarea
    [aria-hidden=true]
    svg
  )

  @keep_attrs %{
    "*"      => [],
    "a"      => ["href"],
    "source" => ["srcset", "media", "type"],
    "figure" => ["src", "alt", "srcset", "data-src", "data-srcset"],
    "img"    => ["src", "alt", "srcset", "data-src", "data-srcset", "data-lazy-src"]
  }

  @doc """
  Parses `html`, extracts body content, removes noise elements, strips
  non-content attributes, removes HTML comments, and returns clean HTML
  trimmed to at most `max_bytes` bytes (default 80KB).
  """
  def strip(html, max_bytes \\ 80_000) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        body = extract_body(tree)

        cleaned =
          Enum.reduce(@remove_selectors, body, fn selector, acc ->
            Floki.filter_out(acc, selector)
          end)
          |> remove_comments()
          |> clean_attributes()
          |> Floki.raw_html()

        binary_part(cleaned, 0, min(byte_size(cleaned), max_bytes))

      {:error, _} ->
        ""
    end
  end

  defp extract_body(tree) do
    case Floki.find(tree, "body") do
      [{"body", _attrs, children} | _] -> children
      _ -> tree
    end
  end

  defp remove_comments(tree) do
    Floki.traverse_and_update(tree, fn
      {:comment, _} -> nil
      other -> other
    end)
  end

  defp clean_attributes(tree) do
    global = Map.get(@keep_attrs, "*", [])

    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} ->
        allowed = global ++ Map.get(@keep_attrs, tag, [])
        kept = Enum.filter(attrs, fn {name, _} -> name in allowed end)
        {tag, kept, children}

      other ->
        other
    end)
  end
end
```

- [ ] **Run HTMLStripper tests**

```bash
mix test test/scientia_cognita/html_stripper_test.exs
```

Expected: all pass. If the Hubble size test fails (still > 100KB), check which elements are still large using:
```bash
mix run -e '
html = File.read!("test/fixtures/hubble_page.html")
result = ScientiaCognita.HTMLStripper.strip(html)
IO.puts("Size: #{byte_size(result)} bytes")
'
```
Adjust `@remove_selectors` or add more attribute filtering until under 100KB.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/html_stripper.ex test/scientia_cognita/html_stripper_test.exs
git commit -m "feat: rewrite HTMLStripper — body-only, drop class/id, svg, comments, 80KB cap"
```

---

## Task 8: Rewrite FetchPageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/fetch_page_worker.ex`
- Modify: `test/scientia_cognita/workers/fetch_page_worker_test.exs`

- [ ] **Update the worker**

Replace the entire file:

```elixir
defmodule ScientiaCognita.Workers.FetchPageWorker do
  @moduledoc """
  Fetches the source URL, saves raw HTML atomically via fsmx transition,
  and enqueues ExtractPageWorker.

  State transitions: pending → fetching → extracting

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, Repo}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[FetchPageWorker] source=#{source_id} url=#{source.url}")

    with {:ok, source} <- fsm_transition(source, "fetching"),
         {:ok, html} <- fetch(source.url),
         {:ok, source} <- fsm_transition(source, "extracting", %{raw_html: html}) do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id, url: source.url} |> ExtractPageWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[FetchPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[FetchPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = fsm_transition(source, "failed", %{error: inspect(reason)})
        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok
    end
  end

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fsm_transition(schema, new_state, params \\ %{}) do
    Ecto.Multi.new()
    |> Fsmx.transition_multi(schema, :transition, new_state, params)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: updated}} -> {:ok, updated}
      {:error, :transition, :invalid_transition, _} -> {:error, :invalid_transition}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Update fetch_page_worker_test.exs**

The happy path test asserts `source.status == "extracting"` and `source.raw_html == html` — these still hold. No changes needed to the assertions. Remove any references to `SourceFSM` if present.

- [ ] **Run fetch_page_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/fetch_page_worker_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/fetch_page_worker.ex \
        test/scientia_cognita/workers/fetch_page_worker_test.exs
git commit -m "feat: rewrite FetchPageWorker to use fsmx transition_multi"
```

---

## Task 9: Rewrite ExtractPageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/extract_page_worker.ex`
- Modify: `test/scientia_cognita/workers/extract_page_worker_test.exs`

- [ ] **Rewrite the worker**

Replace the entire file:

```elixir
defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  For each page URL: strips HTML, calls Gemini to extract gallery items,
  appends a GeminiPageResult to the source, persists items, enqueues
  DownloadImageWorkers, and either loops to the next page (extracting → extracting)
  or transitions to items_loading.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, Repo}
  alias ScientiaCognita.Catalog.GeminiPageResult
  alias ScientiaCognita.Workers.DownloadImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @extract_schema %{
    type: "OBJECT",
    properties: %{
      is_gallery: %{type: "BOOLEAN"},
      gallery_title: %{type: "STRING", nullable: true},
      gallery_description: %{type: "STRING", nullable: true},
      next_page_url: %{type: "STRING", nullable: true},
      items: %{
        type: "ARRAY",
        items: %{
          type: "OBJECT",
          properties: %{
            image_url: %{type: "STRING", nullable: true},
            title: %{type: "STRING", nullable: true},
            description: %{type: "STRING", nullable: true},
            copyright: %{type: "STRING", nullable: true}
          },
          required: ["image_url"]
        }
      }
    },
    required: ["is_gallery", "items"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "url" => url}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[ExtractPageWorker] source=#{source_id} url=#{url}")

    with {:ok, html} <- fetch(url),
         clean_html = HTMLStripper.strip(html),
         {:ok, result} <- call_gemini(clean_html, url),
         :ok <- check_is_gallery(result),
         gemini_page = build_gemini_page(result, url),
         items = build_items(result["items"] || [], source_id),
         {:ok, db_items} <- create_items(items) do

      next_url = result["next_page_url"]
      paginating = next_url && next_url != url
      new_state = if paginating, do: "extracting", else: "items_loading"

      transition_params =
        %{
          pages_fetched: source.pages_fetched + 1,
          total_items: source.total_items + length(db_items),
          next_page_url: next_url,
          gemini_page: gemini_page
        }
        |> then(fn p ->
          if new_state == "items_loading" do
            Map.merge(p, %{
              title: result["gallery_title"],
              description: result["gallery_description"]
            })
          else
            p
          end
        end)

      {:ok, source} = fsm_transition(source, new_state, transition_params)
      :ok = enqueue_downloads(db_items)
      broadcast(source_id, {:source_updated, source})

      if paginating do
        %{source_id: source_id, url: next_url} |> __MODULE__.new() |> Oban.insert()
      end

      :ok
    else
      {:not_gallery} ->
        Logger.warning("[ExtractPageWorker] source=#{source_id} is not a scientific image gallery")
        source = Catalog.get_source!(source_id)
        {:ok, _} = fsm_transition(source, "failed", %{
          error: "Page is not a scientific image gallery. Check the source URL and try again."
        })
        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[ExtractPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = fsm_transition(source, "failed", %{error: inspect(reason)})
        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok
    end
  end

  @doc "Returns the Gemini structured-output schema for item extraction."
  def extract_schema, do: @extract_schema

  @doc "Builds the Gemini prompt for extracting gallery items from a page."
  def build_extract_prompt(clean_html, base_url) do
    """
    Analyze the following HTML page and extract scientific image gallery data.

    Determine if this page is a scientific image gallery (astronomy, microscopy,
    wildlife photography, geological surveys, medical imaging, museum collections,
    or science journalism photo essays). Set is_gallery to false for news articles,
    product pages, blog posts, or pages where images are incidental.

    If is_gallery is true:
    - Set gallery_title and gallery_description from the page content.
    - Find ALL gallery items and for each extract:
      * image_url (REQUIRED): The image URL. If a srcset attribute is present,
        return the URL with the largest width descriptor (e.g. prefer "1600w" over "400w").
        Otherwise use the src attribute. Always return absolute URLs.
      * title: The image heading or title (null if absent).
      * description: A description or caption, summarized to under 300 characters (null if absent).
      * copyright: The copyright or credit line (null if absent).
    - Set next_page_url to the absolute URL of the "next page" link if pagination
      exists (null if this is a single page or the last page).

    Base URL for resolving relative URLs: #{base_url}

    HTML:
    #{clean_html}
    """
  end

  # ---------------------------------------------------------------------------

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_gemini(clean_html, base_url) do
    @gemini.generate_structured(build_extract_prompt(clean_html, base_url), @extract_schema, [])
  end

  defp check_is_gallery(%{"is_gallery" => false}), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}), do: :ok
  defp check_is_gallery(_), do: {:not_gallery}

  defp build_gemini_page(result, url) do
    GeminiPageResult.new(%{
      page_url: url,
      is_gallery: result["is_gallery"],
      gallery_title: result["gallery_title"],
      gallery_description: result["gallery_description"],
      next_page_url: result["next_page_url"],
      raw_items: result["items"] || []
    })
  end

  defp build_items(raw_items, source_id) do
    raw_items
    |> Enum.map(fn item ->
      %{
        title: item["title"] || "Untitled",
        description: item["description"],
        copyright: item["copyright"],
        original_url: item["image_url"],
        source_id: source_id,
        status: "pending"
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.original_url) end)
  end

  defp create_items(items) do
    results =
      Enum.map(items, fn attrs ->
        case Catalog.create_item(attrs) do
          {:ok, item} -> item
          {:error, cs} ->
            Logger.warning("[ExtractPageWorker] item insert failed: #{inspect(cs.errors)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  end

  defp enqueue_downloads(items) do
    Enum.each(items, fn item ->
      if item.original_url do
        %{item_id: item.id} |> DownloadImageWorker.new() |> Oban.insert()
      end
    end)
    :ok
  end

  defp fsm_transition(schema, new_state, params \\ %{}) do
    Ecto.Multi.new()
    |> Fsmx.transition_multi(schema, :transition, new_state, params)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: updated}} -> {:ok, updated}
      {:error, :transition, :invalid_transition, _} -> {:error, :invalid_transition}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Update extract_page_worker_test.exs**

Update assertions that reference the old field names:
- `source.gallery_title` → `source.title`
- `source.gallery_description` → `source.description`

Add an assertion for `gemini_pages` in the happy path test:

```elixir
# After existing assertions:
assert length(source.gemini_pages) == 1
assert hd(source.gemini_pages).items_count == 2
```

The test fixture uses `extracting_source_fixture()` — no change needed there.

- [ ] **Run extract_page_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/extract_page_worker_test.exs
```

Expected: all pass.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/extract_page_worker.ex \
        test/scientia_cognita/workers/extract_page_worker_test.exs
git commit -m "feat: rewrite ExtractPageWorker — fsmx, GeminiPageResult, items_loading"
```

---

## Task 10: Rewrite DownloadImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/download_image_worker.ex`
- Modify: `test/scientia_cognita/workers/download_image_worker_test.exs`

- [ ] **Update the worker**

Replace the `alias` block and `perform/1` function body. Keep `download/1`, `ext_from_content_type/1`, `broadcast/2` unchanged.

```elixir
# Replace alias block:
alias ScientiaCognita.{Catalog, Repo, Storage}
alias ScientiaCognita.Workers.ProcessImageWorker
# Remove: alias ScientiaCognita.ItemFSM

# Replace perform/1:
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
         storage_key = Storage.item_key(item.id, :original, ext),
         {:ok, _} <- @storage.upload(storage_key, binary, content_type: content_type),
         {:ok, item} <- fsm_transition(item, "processing", %{storage_key: storage_key}) do
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

# Add at the bottom before the closing `end`:
defp fsm_transition(schema, new_state, params \\ %{}) do
  Ecto.Multi.new()
  |> Fsmx.transition_multi(schema, :transition, new_state, params)
  |> Repo.transaction()
  |> case do
    {:ok, %{transition: updated}} -> {:ok, updated}
    {:error, :transition, :invalid_transition, _} -> {:error, :invalid_transition}
    {:error, _, reason, _} -> {:error, reason}
  end
end
```

- [ ] **Update download_image_worker_test.exs**

The test asserts `item.status == "processing"` and `item.storage_key != nil`. These still hold. Remove any `ItemFSM` references. The test uses `item_fixture(source)` which creates a `pending` item — this fixture path still works since `status_changeset` is kept.

- [ ] **Run download_image_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/download_image_worker_test.exs
```

Expected: passes.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/download_image_worker.ex \
        test/scientia_cognita/workers/download_image_worker_test.exs
git commit -m "feat: rewrite DownloadImageWorker to use fsmx transition_multi"
```

---

## Task 11: Rewrite ProcessImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/process_image_worker.ex`
- Modify: `test/scientia_cognita/workers/process_image_worker_test.exs`

- [ ] **Update the worker**

Replace alias block and `perform/1`. Keep `download_original/1`, `broadcast/2` unchanged.

```elixir
# Replace alias block:
alias ScientiaCognita.{Catalog, Repo, Storage}
alias ScientiaCognita.Workers.ColorAnalysisWorker
# Remove: alias ScientiaCognita.ItemFSM

# Replace the with chain in perform/1:
with {:ok, original_binary} <- download_original(item.storage_key),
     {:ok, img} <- Image.from_binary(original_binary),
     {:ok, resized} <- Image.thumbnail(img, @target_width,
       height: @target_height, crop: :center),
     {:ok, output_binary} <- Image.write(resized, :memory, suffix: ".jpg", quality: 85),
     processed_key = Storage.item_key(item.id, :processed, ".jpg"),
     {:ok, _} <- @storage.upload(processed_key, output_binary, content_type: "image/jpeg"),
     {:ok, item} <- fsm_transition(item, "color_analysis", %{processed_key: processed_key}) do
  broadcast(item.source_id, {:item_updated, item})
  %{item_id: item_id} |> ColorAnalysisWorker.new() |> Oban.insert()
  :ok

# Error branches (replace ItemFSM references):
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

# Add fsm_transition/3 helper (same as other workers)
```

- [ ] **Run process_image_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/process_image_worker_test.exs
```

Expected: passes.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/process_image_worker.ex \
        test/scientia_cognita/workers/process_image_worker_test.exs
git commit -m "feat: rewrite ProcessImageWorker to use fsmx transition_multi"
```

---

## Task 12: Rewrite ColorAnalysisWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/color_analysis_worker.ex`
- Modify: `test/scientia_cognita/workers/color_analysis_worker_test.exs`

- [ ] **Update the worker**

Replace alias block and `perform/1`. Keep `download_processed/1`, `make_thumbnail/1`, `get_colors/1`, `broadcast/2` unchanged.

```elixir
# Replace alias block:
alias ScientiaCognita.{Catalog, Repo, Storage}
alias ScientiaCognita.Workers.RenderWorker
# Remove: alias ScientiaCognita.ItemFSM

# Replace the with chain — colors are passed directly into the transition:
with {:ok, binary} <- download_processed(item.processed_key),
     {:ok, img} <- Image.from_binary(binary),
     {:ok, thumb_binary} <- make_thumbnail(img),
     colors = get_colors(thumb_binary),
     {:ok, item} <- fsm_transition(item, "render", %{
       text_color: colors["text_color"],
       bg_color: colors["bg_color"],
       bg_opacity: colors["bg_opacity"]
     }) do
  broadcast(item.source_id, {:item_updated, item})
  %{item_id: item_id} |> RenderWorker.new() |> Oban.insert()
  :ok

# Same error branches + fsm_transition/3 helper
```

- [ ] **Update color_analysis_worker_test.exs**

Remove `ItemFSM` references. Assertions on `item.status == "render"`, `item.text_color`, etc. still hold since fsmx writes these atomically via `transition_changeset`.

- [ ] **Run color_analysis_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/color_analysis_worker_test.exs
```

Expected: passes.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/color_analysis_worker.ex \
        test/scientia_cognita/workers/color_analysis_worker_test.exs
git commit -m "feat: rewrite ColorAnalysisWorker to use fsmx transition_multi"
```

---

## Task 13: Rewrite RenderWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/render_worker.ex`
- Modify: `test/scientia_cognita/workers/render_worker_test.exs`

- [ ] **Update the worker**

Replace alias block and `perform/1`. Keep `download_processed/1`, `compose_image/2`, `build_overlay_text/1`, `broadcast/2` unchanged. Add `maybe_complete_source/1`.

```elixir
# Replace alias block:
alias ScientiaCognita.{Catalog, Repo, Storage}
# Remove: alias ScientiaCognita.ItemFSM

# Replace the with chain — processed_key (final rendered image) written atomically:
with {:ok, binary} <- download_processed(item.processed_key),
     {:ok, img} <- Image.from_binary(binary),
     {:ok, composed} <- compose_image(img, item),
     {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
     final_key = Storage.item_key(item.id, :final, ".jpg"),
     {:ok, _} <- @storage.upload(final_key, output_binary, content_type: "image/jpeg"),
     {:ok, item} <- fsm_transition(item, "ready", %{processed_key: final_key}) do
  broadcast(item.source_id, {:item_updated, item})
  maybe_complete_source(item)
  :ok

else
  {:error, :invalid_transition} ->
    Logger.warning("[RenderWorker] invalid transition for item=#{item_id}")
    :ok

  {:error, reason} ->
    Logger.error("[RenderWorker] failed item=#{item_id}: #{inspect(reason)}")
    item = Catalog.get_item!(item_id)
    {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
    broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
    :ok
end
```

Add the completion check and fsm helpers:

```elixir
defp maybe_complete_source(item) do
  source = Catalog.get_source!(item.source_id)

  if source.status == "items_loading" do
    pending_count = Catalog.count_items_not_terminal(source)

    if pending_count == 0 do
      multi =
        Ecto.Multi.new()
        |> Fsmx.transition_multi(source, :transition, "done", %{})

      case Repo.transaction(multi) do
        {:ok, %{transition: done_source}} ->
          broadcast(item.source_id, {:source_updated, done_source})

        {:error, :transition, :invalid_transition, _} ->
          # Race: another RenderWorker or a concurrent failure already closed the source
          :ok

        {:error, _, reason, _} ->
          Logger.error("[RenderWorker] failed to close source=#{item.source_id}: #{inspect(reason)}")
      end
    end
  end
end

defp fsm_transition(schema, new_state, params \\ %{}) do
  Ecto.Multi.new()
  |> Fsmx.transition_multi(schema, :transition, new_state, params)
  |> Repo.transaction()
  |> case do
    {:ok, %{transition: updated}} -> {:ok, updated}
    {:error, :transition, :invalid_transition, _} -> {:error, :invalid_transition}
    {:error, _, reason, _} -> {:error, reason}
  end
end
```

- [ ] **Update render_worker_test.exs**

Remove `ItemFSM` alias. The existing tests check `item.status == "ready"` and `item.processed_key =~ "final"` — these still hold. Add a test for source completion:

```elixir
describe "perform/1 — source completion" do
  test "transitions source to done when last item finishes" do
    source = source_fixture(%{status: "items_loading"})
    item = item_fixture(source, %{
      status: "render",
      processed_key: "items/1/processed.jpg",
      text_color: "#FFFFFF", bg_color: "#000000", bg_opacity: 0.75
    })

    jpeg = File.read!("test/fixtures/test_image.jpg")
    expect(MockHttp, :get, fn _url, _opts -> {:ok, %{status: 200, body: jpeg, headers: %{}}} end)
    expect(MockStorage, :upload, fn _key, _data, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(RenderWorker, %{item_id: item.id})

    source = Catalog.get_source!(source.id)
    assert source.status == "done"
  end
end
```

- [ ] **Run render_worker_test.exs**

```bash
mix test test/scientia_cognita/workers/render_worker_test.exs
```

Expected: all pass including the new source completion test.

- [ ] **Commit**

```bash
git add lib/scientia_cognita/workers/render_worker.ex \
        test/scientia_cognita/workers/render_worker_test.exs
git commit -m "feat: rewrite RenderWorker — fsmx, source completion on items_loading→done"
```

---

## Task 14: Delete old FSM modules and tests

**Files:**
- Delete: `lib/scientia_cognita/source_fsm.ex`
- Delete: `lib/scientia_cognita/item_fsm.ex`
- Delete: `test/scientia_cognita/source_fsm_test.exs`
- Delete: `test/scientia_cognita/item_fsm_test.exs`

- [ ] **Delete the files**

```bash
rm lib/scientia_cognita/source_fsm.ex
rm lib/scientia_cognita/item_fsm.ex
rm test/scientia_cognita/source_fsm_test.exs
rm test/scientia_cognita/item_fsm_test.exs
```

- [ ] **Run full test suite**

```bash
mix test
```

Expected: 0 failures. If anything references `SourceFSM` or `ItemFSM`, fix those references now (grep for them first: `grep -r "SourceFSM\|ItemFSM" lib/ test/`).

- [ ] **Commit**

```bash
git add -A
git commit -m "chore: delete SourceFSM and ItemFSM — replaced by fsmx on schemas"
```

---

## Task 15: Integration test — Layer 1 (mocked, CI)

**Files:**
- Create: `test/scientia_cognita/integration/source_lifecycle_test.exs`

- [ ] **Write the integration test**

```elixir
defmodule ScientiaCognita.Integration.SourceLifecycleTest do
  @moduledoc """
  Full-pipeline integration test for the Source + Item lifecycle.

  Layer 1 (default): uses hubble_page.html fixture, mocked Gemini/HTTP/Storage.
  Layer 2 (@moduletag :live): uses real Gemini API — run with --include live.
  """

  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockGemini, MockHttp, MockStorage}
  alias ScientiaCognita.Workers.{
    FetchPageWorker, ExtractPageWorker,
    DownloadImageWorker, ProcessImageWorker,
    ColorAnalysisWorker, RenderWorker
  }

  setup :verify_on_exit!

  @raw_html File.read!("test/fixtures/hubble_page.html")
  @source_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"
  @test_jpeg File.read!("test/fixtures/test_image.jpg")

  @two_items [
    %{"image_url" => "https://example.com/img1.jpg", "title" => "Orion Nebula",
      "description" => "A stellar nursery.", "copyright" => "NASA"},
    %{"image_url" => "https://example.com/img2.jpg", "title" => "Andromeda Galaxy",
      "description" => "Our nearest galactic neighbour.", "copyright" => nil}
  ]

  @gemini_response %{
    "is_gallery" => true,
    "gallery_title" => "Hubble 35 Years",
    "gallery_description" => "35 years of stunning Hubble imagery",
    "next_page_url" => nil,
    "items" => @two_items
  }

  # ---------------------------------------------------------------------------
  # Happy path: pending → fetching → extracting → items_loading → done
  # ---------------------------------------------------------------------------

  describe "full happy path (single page, 2 items)" do
    setup do
      stub(MockStorage, :upload, fn _key, _data, _opts -> {:ok, %{}} end)
      stub(MockGemini, :generate_structured_with_image, fn _p, _b, _s, _o ->
        {:ok, %{"text_color" => "#FFFFFF", "bg_color" => "#000000", "bg_opacity" => 0.75}}
      end)
      :ok
    end

    test "processes all states through to done" do
      source = source_fixture(%{url: @source_url})

      # --- Step 1: FetchPageWorker ---
      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @raw_html, headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.raw_html == @raw_html

      # --- Step 2: ExtractPageWorker ---
      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @raw_html, headers: %{}}}
      end)
      expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
        {:ok, @gemini_response}
      end)

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: @source_url})

      source = Catalog.get_source!(source.id)
      assert source.status == "items_loading"
      assert source.title == "Hubble 35 Years"
      assert source.description == "35 years of stunning Hubble imagery"
      assert length(source.gemini_pages) == 1
      assert hd(source.gemini_pages).items_count == 2
      assert length(hd(source.gemini_pages).raw_items) == 2

      items = Catalog.list_items_by_source(source)
      assert length(items) == 2
      assert_enqueued worker: DownloadImageWorker, count: 2

      # --- Steps 3-6: Item pipeline for each item ---
      for item <- items do
        # DownloadImageWorker
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg,
                  headers: %{"content-type" => ["image/jpeg"]}}}
        end)
        assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "processing"

        # ProcessImageWorker
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)
        assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "color_analysis"

        # ColorAnalysisWorker
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)
        assert :ok = perform_job(ColorAnalysisWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "render"

        # RenderWorker
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)
        assert :ok = perform_job(RenderWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "ready"
      end

      # After last RenderWorker, source must be done
      source = Catalog.get_source!(source.id)
      assert source.status == "done"
    end
  end

  # ---------------------------------------------------------------------------
  # Paginated source (2 pages)
  # ---------------------------------------------------------------------------

  describe "paginated source" do
    test "accumulates gemini_pages across pages, transitions to items_loading on last page" do
      source = source_fixture(%{url: @source_url, status: "extracting"})

      page1_response = %{
        "is_gallery" => true,
        "gallery_title" => "Hubble Gallery",
        "gallery_description" => "Page 1",
        "next_page_url" => "#{@source_url}?page=2",
        "items" => [hd(@two_items)]
      }

      page2_response = %{
        "is_gallery" => true,
        "gallery_title" => "Hubble Gallery",
        "gallery_description" => "Page 2",
        "next_page_url" => nil,
        "items" => [List.last(@two_items)]
      }

      stub(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @raw_html, headers: %{}}}
      end)

      # Page 1
      expect(MockGemini, :generate_structured, fn _p, _s, _o -> {:ok, page1_response} end)
      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: @source_url})

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert length(source.gemini_pages) == 1

      # Page 2
      expect(MockGemini, :generate_structured, fn _p, _s, _o -> {:ok, page2_response} end)
      assert :ok = perform_job(ExtractPageWorker,
               %{source_id: source.id, url: "#{@source_url}?page=2"})

      source = Catalog.get_source!(source.id)
      assert source.status == "items_loading"
      assert length(source.gemini_pages) == 2
      assert source.pages_fetched == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Error paths
  # ---------------------------------------------------------------------------

  describe "error: not a gallery" do
    test "transitions source to failed with descriptive error" do
      source = source_fixture(%{url: @source_url, status: "extracting"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @raw_html, headers: %{}}}
      end)
      expect(MockGemini, :generate_structured, fn _p, _s, _o ->
        {:ok, %{"is_gallery" => false, "items" => []}}
      end)

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: @source_url})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "not a scientific image gallery"
    end
  end

  describe "error: HTTP failure during fetch" do
    test "transitions source to failed" do
      source = source_fixture()

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "timeout"
    end
  end

  describe "error: Gemini API failure" do
    test "transitions source to failed" do
      source = source_fixture(%{status: "extracting"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @raw_html, headers: %{}}}
      end)
      expect(MockGemini, :generate_structured, fn _p, _s, _o ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: @source_url})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "quota"
    end
  end

  # ---------------------------------------------------------------------------
  # Layer 2 — Live Gemini (HTMLStripper iteration harness)
  # ---------------------------------------------------------------------------

  @moduletag :live

  describe "live Gemini extraction from hubble fixture" do
    test "classifies as gallery and extracts 40 items with absolute image URLs" do
      alias ScientiaCognita.{Gemini, HTMLStripper}
      alias ScientiaCognita.Workers.ExtractPageWorker, as: EW

      clean_html = HTMLStripper.strip(@raw_html)
      prompt = EW.build_extract_prompt(clean_html, @source_url)
      schema = EW.extract_schema()

      assert {:ok, result} = Gemini.generate_structured(prompt, schema, [])

      assert result["is_gallery"] == true,
             "Expected is_gallery=true, got: #{inspect(result)}"

      items = result["items"] || []

      assert length(items) == 40,
             "Expected 40 items, got #{length(items)}"

      assert Enum.all?(items, fn item ->
               is_binary(item["image_url"]) and
                 String.starts_with?(item["image_url"], "http")
             end), "All items must have absolute image_url"

      IO.puts("""

      Live Gemini extraction:
        stripped HTML size:    #{byte_size(clean_html)} bytes
        items found:           #{length(items)}
        gallery_title:         #{result["gallery_title"]}
        sample image_url:      #{get_in(items, [Access.at(0), "image_url"])}
      """)
    end
  end
end
```

- [ ] **Run Layer 1 tests only**

```bash
mix test test/scientia_cognita/integration/source_lifecycle_test.exs
```

Expected: all non-live tests pass. Note: `MockStorage.get_url` is not mocked — `Storage.get_url/1` is called directly on the real module (not through the mock), which is fine as it just builds a URL string.

- [ ] **Verify live test is excluded by default**

```bash
mix test 2>&1 | grep "source_lifecycle"
```

Expected: live test is not run.

- [ ] **Commit**

```bash
git add test/scientia_cognita/integration/source_lifecycle_test.exs
git commit -m "test: add full-pipeline source lifecycle integration test"
```

---

## Task 16: Final verification

- [ ] **Run the full test suite**

```bash
mix test
```

Expected: 0 failures, no warnings about `SourceFSM` or `ItemFSM`.

- [ ] **Check compile with warnings-as-errors**

```bash
mix compile --warning-as-errors
```

Expected: clean compile.

- [ ] **Run precommit**

```bash
mix precommit
```

Expected: clean.

- [ ] **Run live test (manual, requires GEMINI_API_KEY)**

When iterating on HTMLStripper, run this to verify Gemini still extracts 40 items:

```bash
GEMINI_API_KEY=<your_key> mix test --include live \
  test/scientia_cognita/integration/source_lifecycle_test.exs
```

Expected: `items found: 40`, stripped HTML under 100KB. If item count is wrong, adjust HTMLStripper and re-run until correct.

- [ ] **Final commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: final cleanup after formal FSM integration"
```
