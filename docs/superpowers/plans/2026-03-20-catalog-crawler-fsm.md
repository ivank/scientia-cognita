# Catalog Crawler FSM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the catalog crawling pipeline into two explicit FSMs — one for sources (fetch→analyze→extract) and one for items (download→process→color_analysis→render) — with Gemini generating CSS selectors once per source rather than extracting items on every page.

**Architecture:** Pure `SourceFSM` / `ItemFSM` modules validate state transitions; Oban workers drive async execution. `CrawlPageWorker` is replaced by `FetchPageWorker` + `AnalyzePageWorker` + `ExtractPageWorker`. `ProcessImageWorker` is split into `ProcessImageWorker` (resize only) + `ColorAnalysisWorker` + `RenderWorker`.

**Tech Stack:** Elixir/Phoenix 1.8, Oban 2.20 (Lite/SQLite), Floki 0.37 (CSS extraction), Gemini AI (via Req), Image library (libvips), Mox (test mocking), ExUnit/Oban.Testing.

---

## File Structure

**Create:**
- `lib/scientia_cognita/http_behaviour.ex` — callback spec for HTTP client
- `lib/scientia_cognita/http.ex` — real Req wrapper implementing HttpBehaviour
- `lib/scientia_cognita/gemini_behaviour.ex` — callback spec for Gemini client
- `lib/scientia_cognita/storage_behaviour.ex` — callback spec for Storage uploads
- `lib/scientia_cognita/source_fsm.ex` — pure SourceFSM transition validator
- `lib/scientia_cognita/item_fsm.ex` — pure ItemFSM transition validator
- `lib/scientia_cognita/workers/fetch_page_worker.ex`
- `lib/scientia_cognita/workers/analyze_page_worker.ex`
- `lib/scientia_cognita/workers/extract_page_worker.ex`
- `lib/scientia_cognita/workers/color_analysis_worker.ex`
- `lib/scientia_cognita/workers/render_worker.ex`
- `priv/repo/migrations/TIMESTAMP_add_fsm_fields_to_sources.exs`
- `priv/repo/migrations/TIMESTAMP_add_fsm_fields_to_items.exs`
- `test/support/mocks.ex` — Mox mock module definitions
- `test/support/fixtures/catalog_fixtures.ex` — source/item test fixtures
- `test/fixtures/gallery_page.html` — fixture HTML for ExtractPageWorker tests
- `test/scientia_cognita/source_fsm_test.exs`
- `test/scientia_cognita/item_fsm_test.exs`
- `test/scientia_cognita/workers/fetch_page_worker_test.exs`
- `test/scientia_cognita/workers/analyze_page_worker_test.exs`
- `test/scientia_cognita/workers/extract_page_worker_test.exs`
- `test/scientia_cognita/workers/download_image_worker_test.exs`
- `test/scientia_cognita/workers/process_image_worker_test.exs`
- `test/scientia_cognita/workers/color_analysis_worker_test.exs`
- `test/scientia_cognita/workers/render_worker_test.exs`

**Modify:**
- `mix.exs` — add `{:mox, "~> 1.2", only: :test}`
- `config/test.exs` — mock module config + Oban testing mode
- `test/test_helper.exs` — `Mox.defmock` calls
- `lib/scientia_cognita/gemini.ex` — add `@behaviour ScientiaCognita.GeminiBehaviour`
- `lib/scientia_cognita/storage.ex` — add `@behaviour ScientiaCognita.StorageBehaviour`
- `lib/scientia_cognita/catalog/source.ex` — new `@statuses`, `html_changeset/2`, `analyze_changeset/2`
- `lib/scientia_cognita/catalog/item.ex` — new `@statuses`, `color_changeset/2`
- `lib/scientia_cognita/catalog.ex` — new context fns, update `list_stuck_item_ids`
- `lib/scientia_cognita/workers/download_image_worker.ex` — use FSM + Http module
- `lib/scientia_cognita/workers/process_image_worker.ex` — resize/crop only, use Http module
- `lib/scientia_cognita_web/live/console/sources_live.ex` — use FetchPageWorker
- `lib/scientia_cognita_web/live/console/source_show_live.ex` — new statuses + retry logic

**Delete:**
- `lib/scientia_cognita/workers/crawl_page_worker.ex`

---

## Task 1: Add Mox and test infrastructure

**Files:**
- Modify: `mix.exs`
- Modify: `config/test.exs`
- Modify: `test/test_helper.exs`
- Create: `test/support/mocks.ex`
- Create: `lib/scientia_cognita/http_behaviour.ex`
- Create: `lib/scientia_cognita/http.ex`
- Create: `lib/scientia_cognita/gemini_behaviour.ex`
- Create: `lib/scientia_cognita/storage_behaviour.ex`

- [ ] **Step 1: Add Mox to mix.exs**

In `mix.exs`, add after `{:ueberauth_google, "~> 0.12"}`:

```elixir
      # Testing
      {:mox, "~> 1.2", only: :test}
```

- [ ] **Step 2: Install the dependency**

```bash
mix deps.get
```

Expected: `Mox` fetched and compiled.

- [ ] **Step 3: Create HttpBehaviour**

Create `lib/scientia_cognita/http_behaviour.ex`:

```elixir
defmodule ScientiaCognita.HttpBehaviour do
  @callback get(url :: String.t(), opts :: keyword()) ::
              {:ok, %{status: integer(), body: any(), headers: map()}}
              | {:error, term()}
end
```

- [ ] **Step 4: Create Http module (real implementation)**

Create `lib/scientia_cognita/http.ex`:

```elixir
defmodule ScientiaCognita.Http do
  @behaviour ScientiaCognita.HttpBehaviour

  @impl true
  def get(url, opts \\ []) do
    case Req.get(url, opts) do
      {:ok, %{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

- [ ] **Step 5: Create GeminiBehaviour**

Create `lib/scientia_cognita/gemini_behaviour.ex`:

```elixir
defmodule ScientiaCognita.GeminiBehaviour do
  @callback generate_structured(prompt :: String.t(), schema :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback generate_structured_with_image(
              prompt :: String.t(),
              image_binary :: binary(),
              schema :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}
end
```

- [ ] **Step 6: Add @behaviour to Gemini module**

In `lib/scientia_cognita/gemini.ex`, add after `@moduledoc`:

```elixir
  @behaviour ScientiaCognita.GeminiBehaviour
```

- [ ] **Step 7: Create StorageBehaviour**

Create `lib/scientia_cognita/storage_behaviour.ex`:

```elixir
defmodule ScientiaCognita.StorageBehaviour do
  @callback upload(key :: String.t(), binary :: binary(), opts :: keyword()) ::
              {:ok, any()} | {:error, term()}
end
```

- [ ] **Step 8: Add @behaviour to Storage module**

In `lib/scientia_cognita/storage.ex`, find `defmodule ScientiaCognita.Storage do` and add after any existing `@moduledoc`:

```elixir
  @behaviour ScientiaCognita.StorageBehaviour
```

- [ ] **Step 9: Create test/support/mocks.ex**

```elixir
Mox.defmock(ScientiaCognita.MockHttp, for: ScientiaCognita.HttpBehaviour)
Mox.defmock(ScientiaCognita.MockGemini, for: ScientiaCognita.GeminiBehaviour)
Mox.defmock(ScientiaCognita.MockStorage, for: ScientiaCognita.StorageBehaviour)
```

- [ ] **Step 10: Add Mox setup to test/test_helper.exs**

Replace the contents with:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ScientiaCognita.Repo, :manual)

# Define Mox mocks — must happen before tests load
Code.require_file("support/mocks.ex", __DIR__)
```

- [ ] **Step 11: Add mock config to config/test.exs**

Append to `config/test.exs`:

```elixir
# Mock modules for worker tests
config :scientia_cognita, :http_module, ScientiaCognita.MockHttp
config :scientia_cognita, :gemini_module, ScientiaCognita.MockGemini
config :scientia_cognita, :storage_module, ScientiaCognita.MockStorage

# Oban testing mode — jobs do not run automatically
config :scientia_cognita, Oban, testing: :manual
```

- [ ] **Step 12: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 13: Commit**

```bash
git add mix.exs mix.lock config/test.exs test/test_helper.exs test/support/mocks.ex \
  lib/scientia_cognita/http_behaviour.ex lib/scientia_cognita/http.ex \
  lib/scientia_cognita/gemini_behaviour.ex lib/scientia_cognita/storage_behaviour.ex \
  lib/scientia_cognita/gemini.ex lib/scientia_cognita/storage.ex
git commit -m "feat: add Mox, Http/Gemini/Storage behaviours for worker testing"
```

---

## Task 2: Catalog fixtures for tests

**Files:**
- Create: `test/support/fixtures/catalog_fixtures.ex`

- [ ] **Step 1: Create catalog fixtures**

Create `test/support/fixtures/catalog_fixtures.ex`:

```elixir
defmodule ScientiaCognita.CatalogFixtures do
  alias ScientiaCognita.Catalog

  def source_fixture(attrs \\ %{}) do
    {:ok, source} =
      attrs
      |> Enum.into(%{
        name: "Test Gallery",
        url: "https://example.com/gallery",
        status: "pending"
      })
      |> Catalog.create_source()

    source
  end

  def analyzed_source_fixture(attrs \\ %{}) do
    source = source_fixture(Map.merge(%{status: "extracting"}, attrs))

    {:ok, source} =
      Catalog.update_source_analysis(source, %{
        gallery_title: "Test Gallery",
        gallery_description: "A test gallery",
        selector_title: ".item-title",
        selector_image: ".item img",
        selector_description: ".item-desc",
        selector_copyright: ".item-copy",
        selector_next_page: "a.next-page"
      })

    source
  end

  def item_fixture(source, attrs \\ %{}) do
    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image.jpg",
        source_id: source.id,
        status: "pending"
      })
      |> Catalog.create_item()

    item
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add test/support/fixtures/catalog_fixtures.ex
git commit -m "test: add catalog fixtures for source/item tests"
```

---

## Task 3: Database migrations

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_fsm_fields_to_sources.exs`
- Create: `priv/repo/migrations/TIMESTAMP_add_fsm_fields_to_items.exs`

- [ ] **Step 1: Generate sources migration**

```bash
mix ecto.gen.migration add_fsm_fields_to_sources
```

- [ ] **Step 2: Fill in sources migration**

Open the generated file and replace the `change/0` body:

```elixir
def change do
  alter table(:sources) do
    add :raw_html, :text
    add :gallery_title, :string
    add :gallery_description, :string
    add :selector_title, :string
    add :selector_image, :string
    add :selector_description, :string
    add :selector_copyright, :string
    add :selector_next_page, :string
  end
end
```

- [ ] **Step 3: Generate items migration**

```bash
mix ecto.gen.migration add_fsm_fields_to_items
```

- [ ] **Step 4: Fill in items migration**

```elixir
def change do
  alter table(:items) do
    add :text_color, :string
    add :bg_color, :string
    add :bg_opacity, :float
  end
end
```

- [ ] **Step 5: Run migrations**

```bash
mix ecto.migrate
```

Expected: `== Running 2 migrations ==` with no errors.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: add FSM fields to sources and items tables"
```

---

## Task 4: Source schema — new statuses and changesets

**Files:**
- Modify: `lib/scientia_cognita/catalog/source.ex`
- Create: `test/scientia_cognita/catalog/source_test.exs`

- [ ] **Step 1: Write failing tests for new changesets**

Create `test/scientia_cognita/catalog/source_test.exs`:

```elixir
defmodule ScientiaCognita.Catalog.SourceTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.Source

  describe "html_changeset/2" do
    test "casts raw_html" do
      source = %Source{status: "fetching"}
      cs = Source.html_changeset(source, %{raw_html: "<html>content</html>"})
      assert cs.valid?
      assert get_change(cs, :raw_html) == "<html>content</html>"
    end
  end

  describe "analyze_changeset/2" do
    test "casts all selector fields and gallery metadata" do
      source = %Source{status: "analyzing"}

      attrs = %{
        gallery_title: "Hubble Gallery",
        gallery_description: "Space images",
        selector_title: ".caption h3",
        selector_image: ".gallery-item img",
        selector_description: ".caption p",
        selector_copyright: ".credit",
        selector_next_page: "a.next"
      }

      cs = Source.analyze_changeset(source, attrs)
      assert cs.valid?
      assert get_change(cs, :gallery_title) == "Hubble Gallery"
      assert get_change(cs, :selector_image) == ".gallery-item img"
    end
  end

  describe "status_changeset/3" do
    test "accepts new FSM statuses" do
      for status <- ~w(pending fetching analyzing extracting done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects old running status" do
      cs = Source.status_changeset(%Source{status: "pending"}, "running")
      refute cs.valid?
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/scientia_cognita/catalog/source_test.exs
```

Expected: FAIL — `html_changeset/2` and `analyze_changeset/2` not defined, `"running"` still accepted.

- [ ] **Step 3: Update source.ex**

Replace the contents of `lib/scientia_cognita/catalog/source.ex`:

```elixir
defmodule ScientiaCognita.Catalog.Source do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending fetching analyzing extracting done failed)

  schema "sources" do
    field :url, :string
    field :name, :string
    field :status, :string, default: "pending"
    field :next_page_url, :string
    field :pages_fetched, :integer, default: 0
    field :total_items, :integer, default: 0
    field :error, :string

    # FSM fields — set during fetching
    field :raw_html, :string

    # FSM fields — set during analyzing
    field :gallery_title, :string
    field :gallery_description, :string
    field :selector_title, :string
    field :selector_image, :string
    field :selector_description, :string
    field :selector_copyright, :string
    field :selector_next_page, :string

    has_many :items, ScientiaCognita.Catalog.Item

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:url, :name, :status, :next_page_url, :pages_fetched, :total_items, :error])
    |> validate_required([:url, :name])
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint(:url)
  end

  def status_changeset(source, status, opts \\ []) do
    source
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  def progress_changeset(source, attrs) do
    source
    |> cast(attrs, [:next_page_url, :pages_fetched, :total_items])
  end

  @doc "Stores the raw HTML fetched from the source URL."
  def html_changeset(source, attrs) do
    source
    |> cast(attrs, [:raw_html])
  end

  @doc "Stores the Gemini-extracted gallery metadata and CSS selectors."
  def analyze_changeset(source, attrs) do
    source
    |> cast(attrs, [
      :gallery_title,
      :gallery_description,
      :selector_title,
      :selector_image,
      :selector_description,
      :selector_copyright,
      :selector_next_page
    ])
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/catalog/source_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/catalog/source.ex test/scientia_cognita/catalog/source_test.exs
git commit -m "feat: update Source schema with FSM statuses and new changesets"
```

---

## Task 5: Item schema — new statuses and color_changeset

**Files:**
- Modify: `lib/scientia_cognita/catalog/item.ex`
- Create: `test/scientia_cognita/catalog/item_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/catalog/item_test.exs`:

```elixir
defmodule ScientiaCognita.Catalog.ItemTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.Item

  describe "color_changeset/2" do
    test "casts color fields" do
      item = %Item{status: "color_analysis"}

      cs = Item.color_changeset(item, %{
        text_color: "#FFFFFF",
        bg_color: "#1A1A2E",
        bg_opacity: 0.75
      })

      assert cs.valid?
      assert get_change(cs, :text_color) == "#FFFFFF"
      assert get_change(cs, :bg_color) == "#1A1A2E"
      assert get_change(cs, :bg_opacity) == 0.75
    end
  end

  describe "status_changeset/3" do
    test "accepts new FSM statuses" do
      for status <- ~w(pending downloading processing color_analysis render ready failed) do
        cs = Item.status_changeset(%Item{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/scientia_cognita/catalog/item_test.exs
```

Expected: FAIL — `color_changeset/2` not defined, `color_analysis` and `render` not in statuses.

- [ ] **Step 3: Update item.ex**

Replace `lib/scientia_cognita/catalog/item.ex`:

```elixir
defmodule ScientiaCognita.Catalog.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending downloading processing color_analysis render ready failed)

  schema "items" do
    field :title, :string
    field :description, :string
    field :author, :string
    field :copyright, :string
    field :original_url, :string
    field :storage_key, :string
    field :processed_key, :string
    field :status, :string, default: "pending"
    field :error, :string

    # FSM fields — set during color_analysis
    field :text_color, :string
    field :bg_color, :string
    field :bg_opacity, :float

    belongs_to :source, ScientiaCognita.Catalog.Source
    many_to_many :catalogs, ScientiaCognita.Catalog.Catalog,
      join_through: ScientiaCognita.Catalog.CatalogItem

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

  def status_changeset(item, status, opts \\ []) do
    item
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:storage_key, :processed_key])
  end

  @doc "Stores Gemini-determined text overlay colors."
  def color_changeset(item, attrs) do
    item
    |> cast(attrs, [:text_color, :bg_color, :bg_opacity])
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/catalog/item_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/catalog/item.ex test/scientia_cognita/catalog/item_test.exs
git commit -m "feat: update Item schema with FSM statuses and color_changeset"
```

---

## Task 6: Catalog context — new update functions

**Files:**
- Modify: `lib/scientia_cognita/catalog.ex`

- [ ] **Step 1: Add new context functions**

In `lib/scientia_cognita/catalog.ex`, after `update_source_progress/2`, add:

```elixir
  def update_source_html(%Source{} = source, attrs) do
    source
    |> Source.html_changeset(attrs)
    |> Repo.update()
  end

  def update_source_analysis(%Source{} = source, attrs) do
    source
    |> Source.analyze_changeset(attrs)
    |> Repo.update()
  end
```

After `update_item_storage/2`, add:

```elixir
  def update_item_colors(%Item{} = item, attrs) do
    item
    |> Item.color_changeset(attrs)
    |> Repo.update()
  end
```

- [ ] **Step 2: Update list_stuck_item_ids to include new in-progress statuses**

Replace `list_stuck_item_ids/1` in `lib/scientia_cognita/catalog.ex`:

```elixir
  def list_stuck_item_ids(%Source{id: source_id}) do
    in_progress_ids =
      Repo.all(
        from i in Item,
          where:
            i.source_id == ^source_id and
              i.status in ["downloading", "processing", "color_analysis", "render"],
          select: i.id
      )

    if in_progress_ids == [] do
      []
    else
      active_item_ids =
        Repo.all(
          from j in "oban_jobs",
            where:
              j.worker in [
                "ScientiaCognita.Workers.DownloadImageWorker",
                "ScientiaCognita.Workers.ProcessImageWorker",
                "ScientiaCognita.Workers.ColorAnalysisWorker",
                "ScientiaCognita.Workers.RenderWorker"
              ] and
                j.state in ["available", "scheduled", "executing", "retryable"] and
                fragment("CAST(json_extract(args, '$.item_id') AS INTEGER)") in ^in_progress_ids,
            select: fragment("CAST(json_extract(args, '$.item_id') AS INTEGER)")
        )
        |> MapSet.new()

      Enum.reject(in_progress_ids, &MapSet.member?(active_item_ids, &1))
    end
  end
```

- [ ] **Step 3: Run full test suite to verify no regressions**

```bash
mix test
```

Expected: all existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/scientia_cognita/catalog.ex
git commit -m "feat: add update_source_html, update_source_analysis, update_item_colors to Catalog context"
```

---

## Task 7: SourceFSM

**Files:**
- Create: `lib/scientia_cognita/source_fsm.ex`
- Create: `test/scientia_cognita/source_fsm_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/source_fsm_test.exs`:

```elixir
defmodule ScientiaCognita.SourceFSMTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.SourceFSM
  alias ScientiaCognita.Catalog.Source

  defp source(status), do: %Source{status: status}

  describe "valid transitions" do
    test "pending + :start → fetching" do
      assert {:ok, "fetching"} = SourceFSM.transition(source("pending"), :start)
    end

    test "fetching + :fetched → analyzing" do
      assert {:ok, "analyzing"} = SourceFSM.transition(source("fetching"), :fetched)
    end

    test "analyzing + :analyzed → extracting" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("analyzing"), :analyzed)
    end

    test "analyzing + :not_gallery → failed" do
      assert {:ok, "failed"} = SourceFSM.transition(source("analyzing"), :not_gallery)
    end

    test "extracting + :page_done → extracting (self-loop)" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("extracting"), :page_done)
    end

    test "extracting + :exhausted → done" do
      assert {:ok, "done"} = SourceFSM.transition(source("extracting"), :exhausted)
    end

    test ":failed from any non-terminal state" do
      for status <- ~w(pending fetching analyzing extracting) do
        assert {:ok, "failed"} = SourceFSM.transition(source(status), :failed),
               "Expected :failed to work from #{status}"
      end
    end
  end

  describe "invalid transitions" do
    test "wrong event for state" do
      assert {:error, :invalid_transition} = SourceFSM.transition(source("pending"), :fetched)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("fetching"), :start)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("done"), :start)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("failed"), :start)
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/source_fsm_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement SourceFSM**

Create `lib/scientia_cognita/source_fsm.ex`:

```elixir
defmodule ScientiaCognita.SourceFSM do
  @moduledoc """
  Pure state transition validator for Source crawl lifecycle.
  No side effects — only validates whether a transition is allowed.
  """

  alias ScientiaCognita.Catalog.Source

  @spec transition(Source.t(), atom()) :: {:ok, String.t()} | {:error, :invalid_transition}

  def transition(%Source{status: "pending"}, :start), do: {:ok, "fetching"}
  def transition(%Source{status: "fetching"}, :fetched), do: {:ok, "analyzing"}
  def transition(%Source{status: "analyzing"}, :analyzed), do: {:ok, "extracting"}
  def transition(%Source{status: "analyzing"}, :not_gallery), do: {:ok, "failed"}
  def transition(%Source{status: "extracting"}, :page_done), do: {:ok, "extracting"}
  def transition(%Source{status: "extracting"}, :exhausted), do: {:ok, "done"}
  def transition(%Source{status: status}, :failed) when status not in ["done", "failed"],
    do: {:ok, "failed"}
  def transition(_, _), do: {:error, :invalid_transition}
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/source_fsm_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/source_fsm.ex test/scientia_cognita/source_fsm_test.exs
git commit -m "feat: add SourceFSM with TDD"
```

---

## Task 8: ItemFSM

**Files:**
- Create: `lib/scientia_cognita/item_fsm.ex`
- Create: `test/scientia_cognita/item_fsm_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/item_fsm_test.exs`:

```elixir
defmodule ScientiaCognita.ItemFSMTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.ItemFSM
  alias ScientiaCognita.Catalog.Item

  defp item(status), do: %Item{status: status}

  describe "valid transitions" do
    test "pending + :start → downloading" do
      assert {:ok, "downloading"} = ItemFSM.transition(item("pending"), :start)
    end

    test "downloading + :downloaded → processing" do
      assert {:ok, "processing"} = ItemFSM.transition(item("downloading"), :downloaded)
    end

    test "processing + :processed → color_analysis" do
      assert {:ok, "color_analysis"} = ItemFSM.transition(item("processing"), :processed)
    end

    test "color_analysis + :colors_ready → render" do
      assert {:ok, "render"} = ItemFSM.transition(item("color_analysis"), :colors_ready)
    end

    test "render + :rendered → ready" do
      assert {:ok, "ready"} = ItemFSM.transition(item("render"), :rendered)
    end

    test ":failed from any non-terminal state" do
      for status <- ~w(pending downloading processing color_analysis render) do
        assert {:ok, "failed"} = ItemFSM.transition(item(status), :failed),
               "Expected :failed to work from #{status}"
      end
    end
  end

  describe "invalid transitions" do
    test "wrong event for state" do
      assert {:error, :invalid_transition} = ItemFSM.transition(item("pending"), :downloaded)
      assert {:error, :invalid_transition} = ItemFSM.transition(item("ready"), :start)
      assert {:error, :invalid_transition} = ItemFSM.transition(item("failed"), :start)
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/item_fsm_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement ItemFSM**

Create `lib/scientia_cognita/item_fsm.ex`:

```elixir
defmodule ScientiaCognita.ItemFSM do
  @moduledoc """
  Pure state transition validator for Item image pipeline.
  No side effects — only validates whether a transition is allowed.
  """

  alias ScientiaCognita.Catalog.Item

  @spec transition(Item.t(), atom()) :: {:ok, String.t()} | {:error, :invalid_transition}

  def transition(%Item{status: "pending"}, :start), do: {:ok, "downloading"}
  def transition(%Item{status: "downloading"}, :downloaded), do: {:ok, "processing"}
  def transition(%Item{status: "processing"}, :processed), do: {:ok, "color_analysis"}
  def transition(%Item{status: "color_analysis"}, :colors_ready), do: {:ok, "render"}
  def transition(%Item{status: "render"}, :rendered), do: {:ok, "ready"}
  def transition(%Item{status: status}, :failed) when status not in ["ready", "failed"],
    do: {:ok, "failed"}
  def transition(_, _), do: {:error, :invalid_transition}
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/item_fsm_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/item_fsm.ex test/scientia_cognita/item_fsm_test.exs
git commit -m "feat: add ItemFSM with TDD"
```

---

## Task 9: FetchPageWorker

**Files:**
- Create: `lib/scientia_cognita/workers/fetch_page_worker.ex`
- Create: `test/scientia_cognita/workers/fetch_page_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/fetch_page_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.FetchPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp}
  alias ScientiaCognita.Workers.{FetchPageWorker, AnalyzePageWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "fetches HTML, saves raw_html, transitions to analyzing, enqueues AnalyzePageWorker" do
      source = source_fixture(%{status: "pending"})
      html = "<html><body>gallery content</body></html>"

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: html, headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "analyzing"
      assert source.raw_html == html

      assert_enqueued worker: AnalyzePageWorker, args: %{"source_id" => source.id}
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks source as failed on HTTP error" do
      source = source_fixture(%{status: "pending"})

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "timeout"
    end
  end

  describe "perform/1 — non-200 response" do
    test "marks source as failed on non-200 HTTP status" do
      source = source_fixture(%{status: "pending"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 404, body: "Not Found", headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/fetch_page_worker_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement FetchPageWorker**

Create `lib/scientia_cognita/workers/fetch_page_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.FetchPageWorker do
  @moduledoc """
  Fetches the source URL, saves raw HTML to the source record,
  and enqueues AnalyzePageWorker.

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, SourceFSM}
  alias ScientiaCognita.Workers.AnalyzePageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[FetchPageWorker] source=#{source_id} url=#{source.url}")

    with {:ok, "fetching"} <- SourceFSM.transition(source, :start),
         {:ok, source} <- Catalog.update_source_status(source, "fetching"),
         {:ok, html} <- fetch(source.url),
         {:ok, source} <- Catalog.update_source_html(source, %{raw_html: html}),
         {:ok, "analyzing"} <- SourceFSM.transition(source, :fetched),
         {:ok, source} <- Catalog.update_source_status(source, "analyzing") do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id} |> AnalyzePageWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[FetchPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[FetchPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = Catalog.update_source_status(source, "failed", error: inspect(reason))
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

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/workers/fetch_page_worker_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/fetch_page_worker.ex \
  test/scientia_cognita/workers/fetch_page_worker_test.exs
git commit -m "feat: add FetchPageWorker with TDD"
```

---

## Task 10: AnalyzePageWorker

**Files:**
- Create: `lib/scientia_cognita/workers/analyze_page_worker.ex`
- Create: `test/scientia_cognita/workers/analyze_page_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/analyze_page_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.AnalyzePageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockGemini}
  alias ScientiaCognita.Workers.{AnalyzePageWorker, ExtractPageWorker}

  setup :verify_on_exit!

  @gallery_response %{
    "is_gallery" => true,
    "title" => "Hubble Images",
    "description" => "Space telescope photos",
    "selector_title" => ".item-title",
    "selector_image" => ".item img",
    "selector_description" => ".item-desc",
    "selector_copyright" => ".credit",
    "selector_next_page" => "a.next"
  }

  describe "perform/1 — gallery page" do
    test "stores selectors, transitions to extracting, enqueues ExtractPageWorker" do
      source = source_fixture(%{
        status: "analyzing",
        raw_html: "<html>gallery html</html>"
      })

      expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
        {:ok, @gallery_response}
      end)

      assert :ok = perform_job(AnalyzePageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.selector_image == ".item img"
      assert source.gallery_title == "Hubble Images"

      assert_enqueued worker: ExtractPageWorker,
                      args: %{"source_id" => source.id, "url" => source.url}
    end
  end

  describe "perform/1 — not a gallery" do
    test "marks source as failed with descriptive error" do
      source = source_fixture(%{
        status: "analyzing",
        raw_html: "<html>news article</html>"
      })

      expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
        {:ok, %{"is_gallery" => false}}
      end)

      assert :ok = perform_job(AnalyzePageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "not a scientific image gallery"
    end
  end

  describe "perform/1 — Gemini error" do
    test "marks source as failed on Gemini API error" do
      source = source_fixture(%{
        status: "analyzing",
        raw_html: "<html>content</html>"
      })

      expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(AnalyzePageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/analyze_page_worker_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement AnalyzePageWorker**

Create `lib/scientia_cognita/workers/analyze_page_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.AnalyzePageWorker do
  @moduledoc """
  Strips the stored raw_html, sends it to Gemini to:
  1. Classify whether the page is a scientific image gallery.
  2. Extract gallery title and description.
  3. Generate CSS selectors for extracting items on all pages.

  On success, stores selectors on the source and enqueues ExtractPageWorker.

  Args: %{source_id: integer}
  """

  use Oban.Worker, queue: :fetch, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, SourceFSM}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @analyze_schema %{
    type: "OBJECT",
    properties: %{
      is_gallery: %{type: "BOOLEAN"},
      title: %{type: "STRING", nullable: true},
      description: %{type: "STRING", nullable: true},
      selector_title: %{type: "STRING", nullable: true},
      selector_image: %{type: "STRING", nullable: true},
      selector_description: %{type: "STRING", nullable: true},
      selector_copyright: %{type: "STRING", nullable: true},
      selector_next_page: %{type: "STRING", nullable: true}
    },
    required: ["is_gallery"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[AnalyzePageWorker] source=#{source_id}")

    clean_html = HTMLStripper.strip(source.raw_html || "")

    with {:ok, result} <- call_gemini(clean_html, source.url),
         :ok <- check_is_gallery(result, source_id),
         {:ok, "extracting"} <- SourceFSM.transition(source, :analyzed),
         {:ok, source} <- Catalog.update_source_analysis(source, build_analysis(result)),
         {:ok, source} <- Catalog.update_source_status(source, "extracting") do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id, url: source.url} |> ExtractPageWorker.new() |> Oban.insert()
      :ok
    else
      {:not_gallery} ->
        Logger.warning("[AnalyzePageWorker] source=#{source_id} is not a scientific image gallery")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed",
          error: "Page is not a scientific image gallery. Check the source URL and try again.")
        broadcast(source_id, {:source_updated, failed})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[AnalyzePageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[AnalyzePageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        :ok
    end
  end

  defp call_gemini(clean_html, base_url) do
    prompt = """
    Analyze the following HTML page and determine whether it is a scientific image gallery.

    A scientific image gallery is a page whose PRIMARY purpose is to display a curated
    collection of scientific, nature, or educational images — for example: astronomy
    photos, microscopy images, wildlife photography, geological surveys, medical imaging,
    museum collections, or science journalism photo essays.

    Set is_gallery to FALSE if the page is primarily: a news article, a product page,
    a blog post, a social media feed, a search results page, or any page where images
    are incidental rather than the main content.

    If is_gallery is TRUE:
    - Extract the gallery title and description.
    - Provide CSS selectors to extract these fields for EACH gallery item:
      * selector_title: selects the title/caption element for each item
      * selector_image: selects the <img> element for each item
      * selector_description: selects the description/caption element (or null)
      * selector_copyright: selects the copyright/credit element (or null)
      * selector_next_page: selects the <a> link to the next page (or null if none)

    The selectors must work with Floki (CSS selector syntax).
    Base URL for resolving relative paths: #{base_url}

    HTML:
    #{clean_html}
    """

    @gemini.generate_structured(prompt, @analyze_schema, [])
  end

  defp check_is_gallery(%{"is_gallery" => false}, _source_id), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}, _source_id), do: :ok
  defp check_is_gallery(_, _source_id), do: {:not_gallery}

  defp build_analysis(result) do
    %{
      gallery_title: result["title"],
      gallery_description: result["description"],
      selector_title: result["selector_title"],
      selector_image: result["selector_image"],
      selector_description: result["selector_description"],
      selector_copyright: result["selector_copyright"],
      selector_next_page: result["selector_next_page"]
    }
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/workers/analyze_page_worker_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/analyze_page_worker.ex \
  test/scientia_cognita/workers/analyze_page_worker_test.exs
git commit -m "feat: add AnalyzePageWorker with TDD"
```

---

## Task 11: ExtractPageWorker

**Files:**
- Create: `lib/scientia_cognita/workers/extract_page_worker.ex`
- Create: `test/scientia_cognita/workers/extract_page_worker_test.exs`
- Create: `test/fixtures/gallery_page.html`

- [ ] **Step 1: Create HTML fixture**

Create `test/fixtures/gallery_page.html`:

```html
<!DOCTYPE html>
<html>
<body>
  <div class="gallery">
    <div class="item">
      <img src="https://example.com/img1.jpg" alt="Nebula">
      <h3 class="item-title">Orion Nebula</h3>
      <p class="item-desc">A stellar nursery 1,344 light-years away.</p>
      <span class="credit">© NASA/ESA</span>
    </div>
    <div class="item">
      <img src="https://example.com/img2.jpg" alt="Galaxy">
      <h3 class="item-title">Andromeda Galaxy</h3>
      <p class="item-desc">Our nearest spiral galaxy neighbour.</p>
      <span class="credit">© ESA Hubble</span>
    </div>
  </div>
  <a class="next-page" href="https://example.com/gallery?page=2">Next →</a>
</body>
</html>
```

- [ ] **Step 2: Write failing tests**

Create `test/scientia_cognita/workers/extract_page_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.ExtractPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp}
  alias ScientiaCognita.Workers.{ExtractPageWorker, DownloadImageWorker}

  setup :verify_on_exit!

  @fixture_html File.read!("test/fixtures/gallery_page.html")

  @selectors %{
    selector_title: ".item-title",
    selector_image: ".item img",
    selector_description: ".item-desc",
    selector_copyright: ".credit",
    selector_next_page: "a.next-page"
  }

  describe "perform/1 — page with items and next page" do
    test "extracts items, enqueues download workers, follows pagination" do
      source = analyzed_source_fixture(@selectors)

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @fixture_html, headers: %{}}}
      end)

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      items = Catalog.list_items_by_source(source)
      assert length(items) == 2
      assert Enum.any?(items, &(&1.title == "Orion Nebula"))
      assert Enum.any?(items, &(&1.title == "Andromeda Galaxy"))

      # Item download workers enqueued
      assert_enqueued worker: DownloadImageWorker

      # Self-loop for next page
      assert_enqueued worker: ExtractPageWorker,
                      args: %{
                        "source_id" => source.id,
                        "url" => "https://example.com/gallery?page=2"
                      }

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.pages_fetched == 1
      assert source.next_page_url == "https://example.com/gallery?page=2"
    end
  end

  describe "perform/1 — last page (no next)" do
    test "transitions source to done when no next page selector matches" do
      html_no_next = String.replace(@fixture_html, ~r/<a class="next-page".*?<\/a>/s, "")

      source = analyzed_source_fixture(Map.merge(@selectors, %{selector_next_page: "a.next-page"}))

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: html_no_next, headers: %{}}}
      end)

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      source = Catalog.get_source!(source.id)
      assert source.status == "done"
    end
  end
end
```

- [ ] **Step 3: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/extract_page_worker_test.exs
```

Expected: FAIL.

- [ ] **Step 4: Implement ExtractPageWorker**

Create `lib/scientia_cognita/workers/extract_page_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  Fetches one page URL, extracts gallery items using stored CSS selectors (via Floki),
  persists items, enqueues download workers, and either loops to the next page
  or marks the source as done.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, SourceFSM}
  alias ScientiaCognita.Workers.DownloadImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "url" => url}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[ExtractPageWorker] source=#{source_id} url=#{url}")

    with {:ok, html} <- fetch(url),
         items = extract_items(html, source),
         next_url = extract_next_url(html, source),
         {:ok, db_items} <- create_items(items, source_id),
         :ok <- enqueue_downloads(db_items) do
      progress = %{
        pages_fetched: source.pages_fetched + 1,
        total_items: source.total_items + length(db_items),
        next_page_url: next_url
      }

      {:ok, source} = Catalog.update_source_progress(source, progress)
      broadcast(source_id, {:source_updated, source})

      if next_url && next_url != url do
        {:ok, "extracting"} = SourceFSM.transition(source, :page_done)
        %{source_id: source_id, url: next_url} |> __MODULE__.new() |> Oban.insert()
      else
        {:ok, "done"} = SourceFSM.transition(source, :exhausted)
        {:ok, done} = Catalog.update_source_status(source, "done")
        broadcast(source_id, {:source_updated, done})
      end

      :ok
    else
      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        :ok
    end
  end

  # ---------------------------------------------------------------------------

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_items(html, source) do
    {:ok, tree} = Floki.parse_document(html)

    images = tree |> Floki.find(source.selector_image || "") |> Enum.map(&src_from_element/1)
    titles = tree |> Floki.find(source.selector_title || "") |> Enum.map(&Floki.text/1)
    descs  = list_or_empty(tree, source.selector_description)
    copies = list_or_empty(tree, source.selector_copyright)

    count = length(images)

    0..(max(count - 1, -1))
    |> Enum.map(fn i ->
      %{
        title: Enum.at(titles, i, "Untitled"),
        image_url: Enum.at(images, i),
        description: Enum.at(descs, i),
        copyright: Enum.at(copies, i)
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.image_url) end)
  end

  defp extract_next_url(_html, %{selector_next_page: nil}), do: nil

  defp extract_next_url(html, source) do
    {:ok, tree} = Floki.parse_document(html)

    case Floki.find(tree, source.selector_next_page) do
      [el | _] -> el |> Floki.attribute("href") |> List.first()
      [] -> nil
    end
  end

  defp list_or_empty(_tree, nil), do: []

  defp list_or_empty(tree, selector) do
    tree |> Floki.find(selector) |> Enum.map(&Floki.text/1)
  end

  defp src_from_element(el) do
    case Floki.attribute(el, "src") do
      [src | _] when src != "" -> src
      _ ->
        case Floki.attribute(el, "data-src") do
          [src | _] -> src
          _ -> nil
        end
    end
  end

  defp create_items(raw_items, source_id) do
    results =
      Enum.map(raw_items, fn item ->
        attrs = %{
          title: item.title,
          description: item.description,
          copyright: item.copyright,
          original_url: item.image_url,
          source_id: source_id,
          status: "pending"
        }

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

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/workers/extract_page_worker_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita/workers/extract_page_worker.ex \
  test/scientia_cognita/workers/extract_page_worker_test.exs \
  test/fixtures/gallery_page.html
git commit -m "feat: add ExtractPageWorker with CSS selector extraction and TDD"
```

---

## Task 12: Update DownloadImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/download_image_worker.ex`
- Create: `test/scientia_cognita/workers/download_image_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/download_image_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.DownloadImageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockStorage}
  alias ScientiaCognita.Workers.{DownloadImageWorker, ProcessImageWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads image, uploads to storage, transitions to processing, enqueues ProcessImageWorker" do
      source = source_fixture()
      item = item_fixture(source, %{original_url: "https://example.com/image.jpg"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: <<255, 216, 255>>, headers: %{"content-type" => ["image/jpeg"]}}}
      end)

      expect(MockStorage, :upload, fn _key, _binary, _opts -> {:ok, %{}} end)

      assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "processing"
      assert item.storage_key != nil

      assert_enqueued worker: ProcessImageWorker, args: %{"item_id" => item.id}
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

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/download_image_worker_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Rewrite DownloadImageWorker to use FSM and Http module**

Replace `lib/scientia_cognita/workers/download_image_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.DownloadImageWorker do
  @moduledoc """
  Downloads an item's original image from its source URL and uploads it to MinIO.
  On success, enqueues ProcessImageWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :fetch, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, ItemFSM, Storage}
  alias ScientiaCognita.Workers.ProcessImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)

    unless item.original_url do
      Logger.warning("[DownloadImageWorker] item=#{item_id} has no original_url, skipping")
      :ok
    else
      Logger.info("[DownloadImageWorker] item=#{item_id} url=#{item.original_url}")

      with {:ok, "downloading"} <- ItemFSM.transition(item, :start),
           {:ok, item} <- Catalog.update_item_status(item, "downloading"),
           {:ok, {binary, content_type}} <- download(item.original_url),
           ext = ext_from_content_type(content_type),
           storage_key = Storage.item_key(item.id, :original, ext),
           {:ok, _} <- @storage.upload(storage_key, binary, content_type: content_type),
           {:ok, item} <- Catalog.update_item_storage(item, %{storage_key: storage_key}),
           {:ok, "processing"} <- ItemFSM.transition(item, :downloaded),
           {:ok, item} <- Catalog.update_item_status(item, "processing") do
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
          {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
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
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/workers/download_image_worker_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/download_image_worker.ex \
  test/scientia_cognita/workers/download_image_worker_test.exs
git commit -m "feat: update DownloadImageWorker to use FSM and Http module"
```

---

## Task 13: Trim ProcessImageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/process_image_worker.ex`
- Create: `test/scientia_cognita/workers/process_image_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/process_image_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.ProcessImageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockStorage}
  alias ScientiaCognita.Workers.{ProcessImageWorker, ColorAnalysisWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads original, resizes to 1920x1080, uploads processed, transitions to color_analysis" do
      source = source_fixture()
      item = item_fixture(source, %{status: "processing", storage_key: "items/1/original.jpg"})

      # Mock: download original from MinIO
      expect(MockHttp, :get, fn _url, _opts ->
        # Minimal valid JPEG binary (1x1 white pixel)
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      # Mock: upload processed image
      expect(MockStorage, :upload, fn key, _binary, _opts ->
        assert key =~ "processed"
        {:ok, %{}}
      end)

      assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "color_analysis"
      assert item.processed_key != nil

      assert_enqueued worker: ColorAnalysisWorker, args: %{"item_id" => item.id}
    end
  end
end
```

- [ ] **Step 2: Add a small test JPEG to fixtures**

```bash
# Create a 1x1 white JPEG using ImageMagick (requires imagemagick: brew install imagemagick)
convert -size 1x1 xc:white test/fixtures/test_image.jpg
```

If ImageMagick is not available, create a minimal binary JPEG fixture another way, or skip this step and note that a valid JPEG is needed in `test/fixtures/test_image.jpg`.

- [ ] **Step 3: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/process_image_worker_test.exs
```

Expected: FAIL (module has different logic, ColorAnalysisWorker not defined yet).

- [ ] **Step 4: Rewrite ProcessImageWorker — resize/crop only**

Replace `lib/scientia_cognita/workers/process_image_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.ProcessImageWorker do
  @moduledoc """
  Downloads an item's original image from MinIO, resizes and crops it to
  1920×1080 (16:9 FHD), and uploads the processed variant.
  On success, enqueues ColorAnalysisWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, ItemFSM, Storage}
  alias ScientiaCognita.Workers.ColorAnalysisWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @target_width 1920
  @target_height 1080

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[ProcessImageWorker] item=#{item_id}")

    with {:ok, original_binary} <- download_original(item.storage_key),
         {:ok, img} <- Image.from_binary(original_binary),
         {:ok, resized} <- Image.thumbnail(img, @target_width,
           height: @target_height, crop: :center),
         {:ok, output_binary} <- Image.write(resized, :memory, suffix: ".jpg", quality: 85),
         processed_key = Storage.item_key(item.id, :processed, ".jpg"),
         {:ok, _} <- @storage.upload(processed_key, output_binary, content_type: "image/jpeg"),
         {:ok, item} <- Catalog.update_item_storage(item, %{processed_key: processed_key}),
         {:ok, "color_analysis"} <- ItemFSM.transition(item, :processed),
         {:ok, item} <- Catalog.update_item_status(item, "color_analysis") do
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
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  end

  defp download_original(nil), do: {:error, "item has no storage_key"}

  defp download_original(storage_key) do
    url = Storage.get_url(storage_key)

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 5: Run tests — will pass once ColorAnalysisWorker exists (Task 14)**

Skip running this test until after Task 14 is complete.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita/workers/process_image_worker.ex \
  test/scientia_cognita/workers/process_image_worker_test.exs \
  test/fixtures/test_image.jpg
git commit -m "feat: trim ProcessImageWorker to resize/crop only, hand off to ColorAnalysisWorker"
```

---

## Task 14: ColorAnalysisWorker

**Files:**
- Create: `lib/scientia_cognita/workers/color_analysis_worker.ex`
- Create: `test/scientia_cognita/workers/color_analysis_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/color_analysis_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.ColorAnalysisWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockGemini, MockStorage}
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
      item = item_fixture(source, %{
        status: "color_analysis",
        processed_key: "items/1/processed.jpg"
      })

      jpeg = File.read!("test/fixtures/test_image.jpg")

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

      assert_enqueued worker: RenderWorker, args: %{"item_id" => item.id}
    end
  end

  describe "perform/1 — Gemini error" do
    test "falls back to default colors and continues" do
      source = source_fixture()
      item = item_fixture(source, %{
        status: "color_analysis",
        processed_key: "items/1/processed.jpg"
      })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(ColorAnalysisWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      # Falls back to defaults — still progresses
      assert item.status == "render"
      assert item.text_color == "#FFFFFF"
      assert item.bg_color == "#000000"
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/color_analysis_worker_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement ColorAnalysisWorker**

Create `lib/scientia_cognita/workers/color_analysis_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.ColorAnalysisWorker do
  @moduledoc """
  Downloads the processed image, generates a thumbnail, asks Gemini for optimal
  text overlay colors, stores them on the item, and enqueues RenderWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, ItemFSM, Storage}
  alias ScientiaCognita.Workers.RenderWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @default_colors %{"text_color" => "#FFFFFF", "bg_color" => "#000000", "bg_opacity" => 0.75}

  @color_schema %{
    type: "OBJECT",
    properties: %{
      text_color: %{type: "STRING", enum: ["#FFFFFF", "#1A1A1A"]},
      bg_color: %{type: "STRING"},
      bg_opacity: %{type: "NUMBER"}
    },
    required: ["text_color", "bg_color", "bg_opacity"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[ColorAnalysisWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item.processed_key),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, thumb_binary} <- make_thumbnail(img),
         colors = get_colors(thumb_binary),
         {:ok, item} <- Catalog.update_item_colors(item, colors),
         {:ok, "render"} <- ItemFSM.transition(item, :colors_ready),
         {:ok, item} <- Catalog.update_item_status(item, "render") do
      broadcast(item.source_id, {:item_updated, item})
      %{item_id: item_id} |> RenderWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[ColorAnalysisWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ColorAnalysisWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  end

  defp download_processed(nil), do: {:error, "item has no processed_key"}

  defp download_processed(key) do
    case @http.get(Storage.get_url(key), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp make_thumbnail(img) do
    with {:ok, thumb} <- Image.thumbnail(img, 200, height: 200, crop: :center) do
      Image.write(thumb, :memory, suffix: ".jpg", quality: 70)
    end
  end

  defp get_colors(thumb_binary) do
    prompt = """
    Analyze this image and choose colors for a semi-transparent text overlay banner
    placed at the bottom of a 1920×1080 photo.

    - text_color: "#FFFFFF" for dark images, "#1A1A1A" for light images
    - bg_color: a hex color that contrasts well with the image content
    - bg_opacity: a float between 0.60 and 0.85
    """

    case @gemini.generate_structured_with_image(prompt, thumb_binary, @color_schema, []) do
      {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _} = colors} -> colors
      _ -> @default_colors
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/scientia_cognita/workers/color_analysis_worker_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Now run ProcessImageWorker tests too**

```bash
mix test test/scientia_cognita/workers/process_image_worker_test.exs
```

Expected: pass (ColorAnalysisWorker now exists).

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita/workers/color_analysis_worker.ex \
  test/scientia_cognita/workers/color_analysis_worker_test.exs
git commit -m "feat: add ColorAnalysisWorker with TDD"
```

---

## Task 15: RenderWorker

**Files:**
- Create: `lib/scientia_cognita/workers/render_worker.ex`
- Create: `test/scientia_cognita/workers/render_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/scientia_cognita/workers/render_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.RenderWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockStorage}
  alias ScientiaCognita.Workers.RenderWorker

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads processed image, renders text overlay, uploads final, marks ready" do
      source = source_fixture()
      item = item_fixture(source, %{
        status: "render",
        title: "Orion Nebula",
        description: "A stellar nursery",
        processed_key: "items/1/processed.jpg",
        text_color: "#FFFFFF",
        bg_color: "#1A1A2E",
        bg_opacity: 0.75
      })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockStorage, :upload, fn key, _binary, _opts ->
        assert key =~ "final"
        {:ok, %{}}
      end)

      assert :ok = perform_job(RenderWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "ready"
      assert item.processed_key =~ "final"
    end
  end

  describe "perform/1 — uses default colors when item has no colors stored" do
    test "renders with fallback colors if text_color is nil" do
      source = source_fixture()
      item = item_fixture(source, %{
        status: "render",
        processed_key: "items/1/processed.jpg"
        # text_color, bg_color, bg_opacity are nil
      })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockStorage, :upload, fn _key, _binary, _opts -> {:ok, %{}} end)

      assert :ok = perform_job(RenderWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "ready"
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

```bash
mix test test/scientia_cognita/workers/render_worker_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement RenderWorker**

Create `lib/scientia_cognita/workers/render_worker.ex`:

```elixir
defmodule ScientiaCognita.Workers.RenderWorker do
  @moduledoc """
  Downloads the processed 1920×1080 image, renders a text overlay band
  using the stored Gemini-determined colors, and uploads the final image.
  Marks the item as "ready".

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, ItemFSM, Storage}

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @target_width 1920
  @target_height 1080
  @band_height 280

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[RenderWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item.processed_key),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, composed} <- compose_image(img, item),
         {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
         final_key = Storage.item_key(item.id, :final, ".jpg"),
         {:ok, _} <- @storage.upload(final_key, output_binary, content_type: "image/jpeg"),
         {:ok, item} <- Catalog.update_item_storage(item, %{processed_key: final_key}),
         {:ok, "ready"} <- ItemFSM.transition(item, :rendered),
         {:ok, item} <- Catalog.update_item_status(item, "ready") do
      broadcast(item.source_id, {:item_updated, item})
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[RenderWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[RenderWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  end

  defp download_processed(nil), do: {:error, "item has no processed_key"}

  defp download_processed(key) do
    case @http.get(Storage.get_url(key), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp compose_image(img, item) do
    text_color = item.text_color || "#FFFFFF"
    bg_color = item.bg_color || "#000000"
    bg_opacity = item.bg_opacity || 0.75
    overlay_text = build_overlay_text(item)

    text_opts = [
      font_size: 28,
      font_weight: :normal,
      text_fill_color: text_color,
      background_fill_color: bg_color,
      background_fill_opacity: bg_opacity,
      width: @target_width - 120,
      padding: [60, 30],
      align: :left
    ]

    with {:ok, text_img} <- Image.Text.text(overlay_text, text_opts) do
      text_height = Image.height(text_img)
      y_pos = @target_height - text_height
      Image.compose(img, text_img, x: 0, y: max(y_pos, @target_height - @band_height))
    end
  end

  defp build_overlay_text(item) do
    [item.description, item.author && "© #{item.author}", item.copyright]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> case do
      [] -> item.title || ""
      parts -> Enum.join(parts, "\n")
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/scientia_cognita/workers/render_worker_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/render_worker.ex \
  test/scientia_cognita/workers/render_worker_test.exs
git commit -m "feat: add RenderWorker with TDD"
```

---

## Task 16: Update source_show_live.ex

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

- [ ] **Step 1: Update alias block at top of file**

Replace:
```elixir
alias ScientiaCognita.Workers.{CrawlPageWorker, DownloadImageWorker, ProcessImageWorker}
```
With:
```elixir
alias ScientiaCognita.Workers.{
  FetchPageWorker,
  DownloadImageWorker,
  ProcessImageWorker,
  ColorAnalysisWorker,
  RenderWorker
}
```

- [ ] **Step 2: Update restart_source handler (line ~212)**

Replace:
```elixir
{:ok, source} = Catalog.update_source_status(source, "running", error: nil)
Catalog.update_source_progress(source, %{pages_fetched: 0, total_items: 0, next_page_url: nil})

start_url = source.next_page_url || source.url

%{source_id: source.id, url: start_url}
|> CrawlPageWorker.new()
|> Oban.insert()
```

With:
```elixir
{:ok, source} = Catalog.update_source_status(source, "pending", error: nil)
Catalog.update_source_progress(source, %{pages_fetched: 0, total_items: 0, next_page_url: nil})

%{source_id: source.id}
|> FetchPageWorker.new()
|> Oban.insert()
```

- [ ] **Step 3: Update retry_item handler — smart worker selection**

Replace the `retry_item` handler body:

```elixir
def handle_event("retry_item", %{"item-id" => item_id}, socket) do
  item = Catalog.get_item!(item_id)

  {status, worker} =
    cond do
      is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
      is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
      is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
      true -> {"render", RenderWorker}
    end

  {:ok, _} = Catalog.update_item_status(item, status, error: nil)
  %{item_id: item.id} |> worker.new() |> Oban.insert()

  source = Catalog.get_source!(socket.assigns.source.id)
  {:noreply, assign_source_data(socket, source)}
end
```

- [ ] **Step 4: Update retry_failed_items handler similarly**

Replace `retry_failed_items` handler body:

```elixir
def handle_event("retry_failed_items", _, socket) do
  Enum.each(socket.assigns.failed_items, fn item ->
    {status, worker} =
      cond do
        is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
        is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
        is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
        true -> {"render", RenderWorker}
      end

    {:ok, _} = Catalog.update_item_status(item, status, error: nil)
    %{item_id: item.id} |> worker.new() |> Oban.insert()
  end)

  source = Catalog.get_source!(socket.assigns.source.id)

  {:noreply,
   socket
   |> assign_source_data(source)
   |> put_flash(:info, "Retrying #{length(socket.assigns.failed_items)} items")}
end
```

- [ ] **Step 5: Update status_class to include new statuses**

Replace the `status_class` private function block:

```elixir
defp status_class("pending"), do: "badge-ghost"
defp status_class("fetching"), do: "badge-warning animate-pulse"
defp status_class("analyzing"), do: "badge-warning animate-pulse"
defp status_class("extracting"), do: "badge-warning animate-pulse"
defp status_class("done"), do: "badge-success"
defp status_class("ready"), do: "badge-success"
defp status_class("failed"), do: "badge-error"
defp status_class("downloading"), do: "badge-info"
defp status_class("processing"), do: "badge-info"
defp status_class("color_analysis"), do: "badge-info"
defp status_class("render"), do: "badge-info"
defp status_class(_), do: "badge-ghost"
```

- [ ] **Step 6: Update sorted_status_counts to include new statuses**

Find `sorted_status_counts/1` and update the `order` list:

```elixir
defp sorted_status_counts(counts) do
  order = ~w(pending downloading processing color_analysis render ready failed)
  Enum.sort_by(counts, fn {status, _} -> Enum.find_index(order, &(&1 == status)) || 99 end)
end
```

- [ ] **Step 7: Compile and verify no errors**

```bash
mix compile
```

Expected: no errors or warnings about undefined functions.

- [ ] **Step 8: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "feat: update source_show_live for FSM statuses and new workers"
```

---

## Task 17: Update sources_live.ex and delete CrawlPageWorker

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Delete: `lib/scientia_cognita/workers/crawl_page_worker.ex`

- [ ] **Step 1: Update sources_live.ex alias and create_source handler**

In `lib/scientia_cognita_web/live/console/sources_live.ex`:

Replace:
```elixir
alias ScientiaCognita.Workers.CrawlPageWorker
```
With:
```elixir
alias ScientiaCognita.Workers.FetchPageWorker
```

Replace:
```elixir
%{source_id: source.id, url: source.url}
|> CrawlPageWorker.new()
|> Oban.insert()
```
With:
```elixir
%{source_id: source.id}
|> FetchPageWorker.new()
|> Oban.insert()
```

- [ ] **Step 2: Update status_badge in sources_live.ex**

Replace the `status_class` function block:

```elixir
defp status_class("pending"), do: "badge-ghost"
defp status_class("fetching"), do: "badge-warning animate-pulse"
defp status_class("analyzing"), do: "badge-warning animate-pulse"
defp status_class("extracting"), do: "badge-warning animate-pulse"
defp status_class("done"), do: "badge-success"
defp status_class("failed"), do: "badge-error"
defp status_class(_), do: "badge-ghost"
```

Also remove the dead `render_slot(nil)` reference for `"running"` status from the `status_badge` component template:

```heex
defp status_badge(assigns) do
  ~H"""
  <span class={"badge badge-sm #{status_class(@status)}"}>
    {@status}
  </span>
  """
end
```

- [ ] **Step 3: Delete CrawlPageWorker**

```bash
rm lib/scientia_cognita/workers/crawl_page_worker.ex
```

- [ ] **Step 4: Run full test suite**

```bash
mix test
```

Expected: all tests pass, no references to CrawlPageWorker remain.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita_web/live/console/sources_live.ex
git rm lib/scientia_cognita/workers/crawl_page_worker.ex
git commit -m "feat: switch sources_live to FetchPageWorker, remove CrawlPageWorker"
```

---

## Final verification

- [ ] **Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Compile in prod mode to catch any missing clauses**

```bash
MIX_ENV=prod mix compile
```

Expected: no errors.

- [ ] **Run database migrations on dev DB**

```bash
mix ecto.migrate
```

Expected: migrations applied successfully.
