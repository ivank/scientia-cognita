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
