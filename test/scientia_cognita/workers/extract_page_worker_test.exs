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
    %{
      "image_url" => "https://example.com/img1.jpg",
      "title" => "Orion Nebula",
      "description" => "A stellar nursery.",
      "copyright" => "NASA"
    },
    %{
      "image_url" => "https://example.com/img2.jpg",
      "title" => "Andromeda Galaxy",
      "description" => "Our nearest galactic neighbour.",
      "copyright" => nil
    }
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

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      items = Catalog.list_items_by_source(source)
      assert length(items) == 2
      assert Enum.any?(items, &(&1.title == "Orion Nebula"))
      assert Enum.any?(items, &(&1.title == "Andromeda Galaxy"))
      assert Enum.any?(items, &(&1.original_url == "https://example.com/img1.jpg"))

      assert_enqueued(worker: DownloadImageWorker)

      source = Catalog.get_source!(source.id)
      assert source.status == "items_loading"
      assert source.pages_fetched == 1
      assert source.total_items == 2
      assert source.title == "Space Gallery"
      assert source.description == "Stunning space photos"
      assert length(source.gemini_pages) == 1
      assert hd(source.gemini_pages).items_count == 2
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
          %{
            "image_url" => "https://example.com/img1.jpg",
            "title" => "Image 1",
            "description" => nil,
            "copyright" => nil
          }
        ]
      })

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      assert_enqueued(
        worker: ExtractPageWorker,
        args: %{"source_id" => source.id, "url" => "https://example.com/gallery?page=2"}
      )

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

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/page"
               })

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

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "quota"
    end
  end

  describe "HTTP error" do
    test "transitions source to failed" do
      source = extracting_source_fixture()

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

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
          %{
            "image_url" => "https://example.com/img1.jpg",
            "title" => "Valid",
            "description" => nil,
            "copyright" => nil
          },
          %{"image_url" => nil, "title" => "No URL", "description" => nil, "copyright" => nil}
        ]
      })

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      items = Catalog.list_items_by_source(source)
      assert length(items) == 1
      assert hd(items).title == "Valid"
    end
  end
end
