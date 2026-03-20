# Gemini Direct Item Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CSS-selector pipeline (AnalyzePageWorker → ExtractPageWorker) with a single ExtractPageWorker that calls Gemini to extract gallery items directly (image_url, title, description <300 chars, copyright).

**Architecture:** FetchPageWorker (unchanged except it now enqueues ExtractPageWorker directly) → ExtractPageWorker (fetches page, sends stripped HTML to Gemini, receives items array, creates Item records, handles pagination via `next_page_url` from Gemini). AnalyzePageWorker is deleted entirely. The `analyzing` FSM state is removed; `fetched` transitions directly to `extracting`.

**Tech Stack:** Elixir, Oban workers, Ecto migrations, Floki (HTMLStripper only), Gemini API (structured output with items array schema), Mox for tests.

---

## File Map

| Action | File |
|--------|------|
| Modify | `lib/scientia_cognita/source_fsm.ex` |
| Modify | `lib/scientia_cognita/catalog/source.ex` |
| Modify | `lib/scientia_cognita/catalog.ex` |
| Modify | `lib/scientia_cognita/html_stripper.ex` |
| Modify | `lib/scientia_cognita/workers/fetch_page_worker.ex` |
| Rewrite | `lib/scientia_cognita/workers/extract_page_worker.ex` |
| Delete | `lib/scientia_cognita/workers/analyze_page_worker.ex` |
| Create | `priv/repo/migrations/20260320200000_drop_selector_fields_from_sources.exs` |
| Modify | `test/scientia_cognita/source_fsm_test.exs` |
| Modify | `test/scientia_cognita/catalog/source_test.exs` |
| Modify | `test/scientia_cognita/workers/fetch_page_worker_test.exs` |
| Rewrite | `test/scientia_cognita/workers/extract_page_worker_test.exs` |
| Modify | `test/support/fixtures/catalog_fixtures.ex` |
| Rewrite | `test/scientia_cognita/integration/hubble_extraction_test.exs` |
| Delete | `test/scientia_cognita/workers/analyze_page_worker_test.exs` |

---

## Task 1: Update SourceFSM

**Files:**
- Modify: `lib/scientia_cognita/source_fsm.ex`
- Modify: `test/scientia_cognita/source_fsm_test.exs`

- [ ] **Step 1: Update the FSM test to reflect the new transitions**

Replace the contents of `test/scientia_cognita/source_fsm_test.exs`:

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

    test "fetching + :fetched → extracting (no longer analyzing)" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("fetching"), :fetched)
    end

    test "extracting + :not_gallery → failed" do
      assert {:ok, "failed"} = SourceFSM.transition(source("extracting"), :not_gallery)
    end

    test "extracting + :page_done → extracting (self-loop)" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("extracting"), :page_done)
    end

    test "extracting + :exhausted → done" do
      assert {:ok, "done"} = SourceFSM.transition(source("extracting"), :exhausted)
    end

    test ":failed from any non-terminal state" do
      for status <- ~w(pending fetching extracting) do
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

    test "analyzing state no longer exists" do
      assert {:error, :invalid_transition} = SourceFSM.transition(source("analyzing"), :analyzed)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("analyzing"), :not_gallery)
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/scientia_cognita/source_fsm_test.exs
```

Expected: failures on `fetched → extracting` (got `analyzing`), and the deleted `:not_gallery` tests.

- [ ] **Step 3: Rewrite `lib/scientia_cognita/source_fsm.ex`**

```elixir
defmodule ScientiaCognita.SourceFSM do
  @moduledoc """
  Pure state transition validator for Source crawl lifecycle.
  No side effects — only validates whether a transition is allowed.
  """

  alias ScientiaCognita.Catalog.Source

  @spec transition(Source.t(), atom()) :: {:ok, String.t()} | {:error, :invalid_transition}

  def transition(%Source{status: "pending"}, :start), do: {:ok, "fetching"}
  def transition(%Source{status: "fetching"}, :fetched), do: {:ok, "extracting"}
  def transition(%Source{status: "extracting"}, :not_gallery), do: {:ok, "failed"}
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

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/source_fsm.ex test/scientia_cognita/source_fsm_test.exs
git commit -m "feat: remove analyzing state from SourceFSM, fetched goes directly to extracting"
```

---

## Task 2: Drop Selector Columns and Update Source Schema

**Files:**
- Create: `priv/repo/migrations/20260320200000_drop_selector_fields_from_sources.exs`
- Modify: `lib/scientia_cognita/catalog/source.ex`
- Modify: `test/scientia_cognita/catalog/source_test.exs`

- [ ] **Step 1: Update source_test.exs to reflect the schema changes**

Replace the contents of `test/scientia_cognita/catalog/source_test.exs`:

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
    test "casts gallery_title and gallery_description only" do
      source = %Source{status: "extracting"}

      attrs = %{
        gallery_title: "Hubble Gallery",
        gallery_description: "Space images"
      }

      cs = Source.analyze_changeset(source, attrs)
      assert cs.valid?
      assert get_change(cs, :gallery_title) == "Hubble Gallery"
      assert get_change(cs, :gallery_description) == "Space images"
    end

    test "does not cast selector fields (they no longer exist)" do
      source = %Source{status: "extracting"}
      cs = Source.analyze_changeset(source, %{gallery_title: "Test", selector_image: ".foo"})
      assert cs.valid?
      # selector_image is not a schema field; cast silently ignores unknown keys
      assert get_change(cs, :gallery_title) == "Test"
    end
  end

  describe "status_changeset/3" do
    test "accepts FSM statuses" do
      for status <- ~w(pending fetching extracting done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects analyzing (removed from FSM)" do
      cs = Source.status_changeset(%Source{status: "pending"}, "analyzing")
      refute cs.valid?
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

Expected: failures because `analyzing` is still in statuses and selector fields still exist.

- [ ] **Step 3: Create the migration**

Create `priv/repo/migrations/20260320200000_drop_selector_fields_from_sources.exs`:

```elixir
defmodule ScientiaCognita.Repo.Migrations.DropSelectorFieldsFromSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      remove :selector_title, :string
      remove :selector_image, :string
      remove :selector_description, :string
      remove :selector_copyright, :string
      remove :selector_next_page, :string
    end
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
mix ecto.migrate
```

Expected: migration applied successfully.

- [ ] **Step 5: Update `lib/scientia_cognita/catalog/source.ex`**

```elixir
defmodule ScientiaCognita.Catalog.Source do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending fetching extracting done failed)

  schema "sources" do
    field :url, :string
    field :name, :string
    field :status, :string, default: "pending"
    field :next_page_url, :string
    field :pages_fetched, :integer, default: 0
    field :total_items, :integer, default: 0
    field :error, :string

    # Set during fetching
    field :raw_html, :string

    # Set during extracting (from Gemini)
    field :gallery_title, :string
    field :gallery_description, :string

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

  @doc "Stores the Gemini-extracted gallery metadata."
  def analyze_changeset(source, attrs) do
    source
    |> cast(attrs, [:gallery_title, :gallery_description])
  end
end
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/catalog/source_test.exs
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations/20260320200000_drop_selector_fields_from_sources.exs \
        lib/scientia_cognita/catalog/source.ex \
        test/scientia_cognita/catalog/source_test.exs
git commit -m "feat: drop selector columns from sources, remove analyzing state from Source schema"
```

---

## Task 3: Add `extracting_source_fixture` to Fixtures

**Files:**
- Modify: `test/support/fixtures/catalog_fixtures.ex`

> **Important ordering note:** This task only ADDS `extracting_source_fixture`. The old `analyzed_source_fixture` is kept until Task 6, when the only test that uses it (`analyze_page_worker_test.exs`) is deleted. Removing it now would break 9 callsites in the existing `extract_page_worker_test.exs` before it is rewritten in Task 5.

- [ ] **Step 1: Add `extracting_source_fixture/1` to `test/support/fixtures/catalog_fixtures.ex`**

Insert after the `source_fixture/1` function (before `item_fixture/2`):

```elixir
  @doc "Creates a source in `extracting` status — ready for ExtractPageWorker."
  def extracting_source_fixture(attrs \\ %{}) do
    source = source_fixture(attrs)
    {:ok, source} = Catalog.update_source_status(source, "extracting")
    source
  end
```

- [ ] **Step 2: Confirm nothing is broken**

```bash
mix test
```

Expected: all tests still pass (we only added a function, did not remove anything).

- [ ] **Step 3: Commit**

```bash
git add test/support/fixtures/catalog_fixtures.ex
git commit -m "refactor: add extracting_source_fixture to CatalogFixtures"
```

---

## Task 4: Update FetchPageWorker

**Files:**
- Modify: `lib/scientia_cognita/workers/fetch_page_worker.ex`
- Modify: `test/scientia_cognita/workers/fetch_page_worker_test.exs`

- [ ] **Step 1: Update the FetchPageWorker test**

Replace contents of `test/scientia_cognita/workers/fetch_page_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.FetchPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp}
  alias ScientiaCognita.Workers.{FetchPageWorker, ExtractPageWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "fetches HTML, saves raw_html, transitions to extracting, enqueues ExtractPageWorker" do
      source = source_fixture(%{status: "pending"})
      html = "<html><body>gallery content</body></html>"

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: html, headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.raw_html == html

      assert_enqueued worker: ExtractPageWorker,
                      args: %{"source_id" => source.id, "url" => source.url}
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

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/scientia_cognita/workers/fetch_page_worker_test.exs
```

Expected: the happy-path test fails (`status == "analyzing"` and `AnalyzePageWorker` enqueued).

- [ ] **Step 3: Update `lib/scientia_cognita/workers/fetch_page_worker.ex`**

```elixir
defmodule ScientiaCognita.Workers.FetchPageWorker do
  @moduledoc """
  Fetches the source URL, saves raw HTML to the source record,
  and enqueues ExtractPageWorker.

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, SourceFSM}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[FetchPageWorker] source=#{source_id} url=#{source.url}")

    with {:ok, "fetching"} <- SourceFSM.transition(source, :start),
         {:ok, source} <- Catalog.update_source_status(source, "fetching"),
         {:ok, html} <- fetch(source.url),
         {:ok, source} <- Catalog.update_source_html(source, %{raw_html: html}),
         {:ok, "extracting"} <- SourceFSM.transition(source, :fetched),
         {:ok, source} <- Catalog.update_source_status(source, "extracting") do
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

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/fetch_page_worker.ex \
        test/scientia_cognita/workers/fetch_page_worker_test.exs
git commit -m "feat: FetchPageWorker now enqueues ExtractPageWorker, transitions to extracting"
```

---

## Task 5: Rewrite ExtractPageWorker

**Files:**
- Rewrite: `lib/scientia_cognita/workers/extract_page_worker.ex`
- Rewrite: `test/scientia_cognita/workers/extract_page_worker_test.exs`

- [ ] **Step 1: Write the new ExtractPageWorker tests**

Replace the full contents of `test/scientia_cognita/workers/extract_page_worker_test.exs`:

```elixir
defmodule ScientiaCognita.Workers.ExtractPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockGemini, MockHttp}
  alias ScientiaCognita.Workers.{ExtractPageWorker, DownloadImageWorker}

  setup :verify_on_exit!

  @gallery_html "<html><body>gallery content</body></html>"

  @two_items [
    %{"image_url" => "https://example.com/img1.jpg", "title" => "Orion Nebula",
      "description" => "A stellar nursery.", "copyright" => "NASA"},
    %{"image_url" => "https://example.com/img2.jpg", "title" => "Andromeda Galaxy",
      "description" => "Our nearest galactic neighbour.", "copyright" => nil}
  ]

  defp http_ok(html \\ @gallery_html) do
    expect(MockHttp, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: html, headers: %{}}}
    end)
  end

  defp gemini_ok(result) do
    expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
      {:ok, result}
    end)
  end

  describe "gallery with items, no next page" do
    test "creates items, enqueues downloads, transitions source to done" do
      source = extracting_source_fixture()
      http_ok()
      gemini_ok(%{
        "is_gallery" => true,
        "gallery_title" => "Space Gallery",
        "gallery_description" => "Stunning space photos",
        "next_page_url" => nil,
        "items" => @two_items
      })

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/gallery"})

      items = Catalog.list_items_by_source(source)
      assert length(items) == 2
      assert Enum.any?(items, &(&1.title == "Orion Nebula"))
      assert Enum.any?(items, &(&1.title == "Andromeda Galaxy"))
      assert Enum.any?(items, &(&1.original_url == "https://example.com/img1.jpg"))

      assert_enqueued worker: DownloadImageWorker

      source = Catalog.get_source!(source.id)
      assert source.status == "done"
      assert source.pages_fetched == 1
      assert source.total_items == 2
      assert source.gallery_title == "Space Gallery"
      assert source.gallery_description == "Stunning space photos"
    end
  end

  describe "gallery with pagination" do
    test "enqueues self with next_page_url, keeps status extracting" do
      source = extracting_source_fixture()
      http_ok()
      gemini_ok(%{
        "is_gallery" => true,
        "gallery_title" => "Space Gallery",
        "gallery_description" => nil,
        "next_page_url" => "https://example.com/gallery?page=2",
        "items" => [
          %{"image_url" => "https://example.com/img1.jpg", "title" => "Image 1",
            "description" => nil, "copyright" => nil}
        ]
      })

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/gallery"})

      assert_enqueued worker: ExtractPageWorker,
                      args: %{"source_id" => source.id, "url" => "https://example.com/gallery?page=2"}

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.next_page_url == "https://example.com/gallery?page=2"
      assert source.pages_fetched == 1
    end
  end

  describe "not a gallery" do
    test "transitions source to failed with descriptive error" do
      source = extracting_source_fixture()
      http_ok()
      gemini_ok(%{"is_gallery" => false, "items" => []})

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/page"})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "not a scientific image gallery"
    end
  end

  describe "Gemini API error" do
    test "transitions source to failed" do
      source = extracting_source_fixture()
      http_ok()

      expect(MockGemini, :generate_structured, fn _prompt, _schema, _opts ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/gallery"})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "quota"
    end
  end

  describe "HTTP error" do
    test "transitions source to failed" do
      source = extracting_source_fixture()

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/gallery"})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
    end
  end

  describe "items with nil image_url are skipped" do
    test "items without image_url are not persisted" do
      source = extracting_source_fixture()
      http_ok()
      gemini_ok(%{
        "is_gallery" => true,
        "gallery_title" => "Gallery",
        "gallery_description" => nil,
        "next_page_url" => nil,
        "items" => [
          %{"image_url" => "https://example.com/img1.jpg", "title" => "Valid", "description" => nil, "copyright" => nil},
          %{"image_url" => nil, "title" => "No URL", "description" => nil, "copyright" => nil}
        ]
      })

      assert :ok = perform_job(ExtractPageWorker, %{source_id: source.id, url: "https://example.com/gallery"})

      items = Catalog.list_items_by_source(source)
      assert length(items) == 1
      assert hd(items).title == "Valid"
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/scientia_cognita/workers/extract_page_worker_test.exs
```

Expected: compilation errors or failures because the existing ExtractPageWorker has a different shape.

- [ ] **Step 3: Rewrite `lib/scientia_cognita/workers/extract_page_worker.ex`**

```elixir
defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  Fetches one page URL, strips HTML, calls Gemini to extract gallery items
  directly (image_url, title, description, copyright), persists items,
  enqueues download workers, and either loops to the next page or marks
  the source as done.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, SourceFSM}
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
         :ok <- check_is_gallery(result, source_id, source),
         {:ok, source} <- store_gallery_info(result, source),
         items = build_items(result["items"] || [], source_id),
         {:ok, db_items} <- create_items(items),
         :ok <- enqueue_downloads(db_items) do

      next_url = result["next_page_url"]
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
      {:not_gallery} ->
        Logger.warning("[ExtractPageWorker] source=#{source_id} is not a scientific image gallery")
        source = Catalog.get_source!(source_id)
        {:ok, "failed"} = SourceFSM.transition(source, :not_gallery)
        {:ok, failed} = Catalog.update_source_status(source, "failed",
          error: "Page is not a scientific image gallery. Check the source URL and try again.")
        broadcast(source_id, {:source_updated, failed})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[ExtractPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
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

  defp check_is_gallery(%{"is_gallery" => false}, _source_id, _source), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}, _source_id, _source), do: :ok
  defp check_is_gallery(_, _source_id, _source), do: {:not_gallery}

  defp store_gallery_info(result, source) do
    Catalog.update_source_analysis(source, %{
      gallery_title: result["gallery_title"],
      gallery_description: result["gallery_description"]
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

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/scientia_cognita/workers/extract_page_worker_test.exs
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita/workers/extract_page_worker.ex \
        test/scientia_cognita/workers/extract_page_worker_test.exs
git commit -m "feat: rewrite ExtractPageWorker to use Gemini for direct item extraction"
```

---

## Task 6: Delete AnalyzePageWorker, Update Integration Test, Simplify HTMLStripper

**Files:**
- Delete: `lib/scientia_cognita/workers/analyze_page_worker.ex`
- Delete: `test/scientia_cognita/workers/analyze_page_worker_test.exs`
- Rewrite: `test/scientia_cognita/integration/hubble_extraction_test.exs` — must happen in this same task before `mix test` is run, because after deleting `AnalyzePageWorker` the integration test will have a compile error if left unchanged
- Modify: `test/support/fixtures/catalog_fixtures.ex` — remove `analyzed_source_fixture` (now safe because `analyze_page_worker_test.exs` is deleted and the rewritten `extract_page_worker_test.exs` uses `extracting_source_fixture`)
- Modify: `lib/scientia_cognita/html_stripper.ex`

- [ ] **Step 1: Delete the old worker and its test**

```bash
rm lib/scientia_cognita/workers/analyze_page_worker.ex
rm test/scientia_cognita/workers/analyze_page_worker_test.exs
```

- [ ] **Step 2: Rewrite `test/scientia_cognita/integration/hubble_extraction_test.exs`**

The existing file references `AnalyzePageWorker` which no longer exists. Replace its contents:

```elixir
defmodule ScientiaCognita.Integration.HubbleExtractionTest do
  @moduledoc """
  Live integration test for the Gemini direct-extraction pipeline.

  Skipped by default. Run explicitly with:

      mix test --include live test/scientia_cognita/integration/hubble_extraction_test.exs

  Requires GEMINI_API_KEY to be set in the environment.
  """

  use ScientiaCognita.DataCase

  @moduletag :live

  alias ScientiaCognita.{Gemini, HTMLStripper}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @raw_html File.read!("test/fixtures/hubble_page.html")
  @source_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"

  describe "Gemini direct extraction on Hubble fixture" do
    test "classifies as gallery and extracts 40 items with image URLs" do
      clean_html = HTMLStripper.strip(@raw_html)
      prompt = ExtractPageWorker.build_extract_prompt(clean_html, @source_url)
      schema = ExtractPageWorker.extract_schema()

      assert {:ok, result} = Gemini.generate_structured(prompt, schema, [])

      assert result["is_gallery"] == true,
             "Expected is_gallery=true, got: #{inspect(result)}"

      items = result["items"] || []

      assert length(items) == 40,
             "Expected 40 items, got #{length(items)}"

      assert Enum.all?(items, fn item ->
               is_binary(item["image_url"]) and String.starts_with?(item["image_url"], "http")
             end),
             "All items must have absolute image_url"

      assert Enum.all?(items, fn item ->
               is_nil(item["description"]) or
                 String.length(item["description"]) <= 300
             end),
             "All descriptions must be <= 300 characters"

      IO.puts("""

      Gemini extraction for Hubble page:
        items found:       #{length(items)}
        gallery_title:     #{result["gallery_title"]}
        next_page_url:     #{result["next_page_url"]}
        sample image_url:  #{get_in(items, [Access.at(0), "image_url"])}
        sample title:      #{get_in(items, [Access.at(0), "title"])}
      """)
    end
  end
end
```

- [ ] **Step 3: Remove `analyzed_source_fixture` from `test/support/fixtures/catalog_fixtures.ex`**

Delete the `analyzed_source_fixture/1` function. It is no longer referenced anywhere (the test that used it was just deleted).

- [ ] **Step 5: Simplify HTMLStripper — remove `strip_for_analysis/1`**

`strip_for_analysis` was only used by the now-deleted AnalyzePageWorker. Replace `lib/scientia_cognita/html_stripper.ex` with the single-function version:

```elixir
defmodule ScientiaCognita.HTMLStripper do
  @moduledoc """
  Strips an HTML document down to clean semantic content suitable for
  passing to an LLM (Gemini) for structured data extraction.

  Removes: scripts, styles, nav, header, footer, ads, all non-essential attributes.
  Keeps: class/id on all elements; href on <a>; src/srcset/alt on <img>/<figure>.
  """

  @remove_selectors ~w(
    script style noscript iframe
    nav header footer aside
    [role=navigation] [role=banner] [role=contentinfo]
    .nav .navbar .menu .sidebar .footer .header .ad .ads .advertisement
    form button input select textarea
    [aria-hidden=true]
  )

  # Attributes kept per tag. The special key "*" applies to all tags.
  @keep_attrs %{
    "*" => ["class", "id"],
    "a" => ["href", "class", "id"],
    "figure" => ["src", "alt", "srcset", "class", "id"],
    "img" => ["src", "alt", "srcset", "class", "id"]
  }

  @doc """
  Parses `html`, removes noise elements and non-content attributes,
  and returns a clean HTML string trimmed to at most `max_bytes` bytes.
  """
  def strip(html, max_bytes \\ 300_000) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        cleaned =
          Enum.reduce(@remove_selectors, tree, fn selector, acc ->
            Floki.filter_out(acc, selector)
          end)
          |> clean_attributes()
          |> Floki.raw_html()

        binary_part(cleaned, 0, min(byte_size(cleaned), max_bytes))

      {:error, _} ->
        ""
    end
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

- [ ] **Step 3: Run the full test suite to confirm no regressions**

```bash
mix test
```

Expected: all green. (If other files still reference `AnalyzePageWorker` or `analyzed_source_fixture`, fix those references now.)

- [ ] **Step 6: Run the full test suite to confirm no regressions**

```bash
mix test
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/scientia_cognita/html_stripper.ex \
        test/scientia_cognita/integration/hubble_extraction_test.exs \
        test/support/fixtures/catalog_fixtures.ex
git commit -m "chore: delete AnalyzePageWorker, update integration test, simplify HTMLStripper"
```

---

**Files:**
- Rewrite: `test/scientia_cognita/integration/hubble_extraction_test.exs`

The integration test previously tested the Gemini → CSS selector → Floki pipeline. Rewrite it to test the new Gemini → direct items pipeline against the real fixture.

- [ ] **Step 1: Rewrite `test/scientia_cognita/integration/hubble_extraction_test.exs`**

```elixir
defmodule ScientiaCognita.Integration.HubbleExtractionTest do
  @moduledoc """
  Live integration test for the Gemini direct-extraction pipeline.

  Skipped by default. Run explicitly with:

      mix test --include live test/scientia_cognita/integration/hubble_extraction_test.exs

  Requires GEMINI_API_KEY to be set in the environment.
  """

  use ScientiaCognita.DataCase

  @moduletag :live

  alias ScientiaCognita.{Gemini, HTMLStripper}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @raw_html File.read!("test/fixtures/hubble_page.html")
  @source_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"

  describe "Gemini direct extraction on Hubble fixture" do
    test "classifies as gallery and extracts 40 items with image URLs" do
      clean_html = HTMLStripper.strip(@raw_html)
      prompt = ExtractPageWorker.build_extract_prompt(clean_html, @source_url)
      schema = ExtractPageWorker.extract_schema()

      assert {:ok, result} = Gemini.generate_structured(prompt, schema, [])

      assert result["is_gallery"] == true,
             "Expected is_gallery=true, got: #{inspect(result)}"

      items = result["items"] || []

      assert length(items) == 40,
             "Expected 40 items, got #{length(items)}"

      assert Enum.all?(items, fn item ->
               is_binary(item["image_url"]) and String.starts_with?(item["image_url"], "http")
             end),
             "All items must have absolute image_url"

      assert Enum.all?(items, fn item ->
               is_nil(item["description"]) or
                 String.length(item["description"]) <= 300
             end),
             "All descriptions must be <= 300 characters"

      IO.puts("""

      Gemini extraction for Hubble page:
        items found:       #{length(items)}
        gallery_title:     #{result["gallery_title"]}
        next_page_url:     #{result["next_page_url"]}
        sample image_url:  #{get_in(items, [Access.at(0), "image_url"])}
        sample title:      #{get_in(items, [Access.at(0), "title"])}
      """)
    end
  end
end
```

---

## Done

All tasks complete. The pipeline is now:

```
FetchPageWorker → ExtractPageWorker (Gemini) → DownloadImageWorker
pending → fetching → extracting → done | failed
```

To verify end-to-end with a live Gemini call:
```bash
mix test --include live test/scientia_cognita/integration/hubble_extraction_test.exs
```
