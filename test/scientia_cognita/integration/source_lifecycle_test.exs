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

  alias ScientiaCognita.{Catalog, MockGemini, MockHttp, MockUploader}

  alias ScientiaCognita.Workers.{
    FetchPageWorker,
    ExtractPageWorker,
    DownloadImageWorker,
    ThumbnailWorker,
    AnalyzeWorker,
    ResizeWorker,
    RenderWorker
  }

  setup :verify_on_exit!

  @raw_html File.read!("test/fixtures/hubble_page.html")
  @source_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"
  @test_jpeg File.read!("test/fixtures/test_image.jpg")

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
      # stub allows multiple calls without strict count tracking
      stub(MockUploader, :store, fn {_upload, _item} -> {:ok, "image.jpg"} end)
      stub(MockUploader, :url, fn _ -> "http://localhost:9000/images/test.jpg" end)

      stub(MockGemini, :generate_structured_with_image, fn _p, _b, _s, _o ->
        {:ok,
         %{
           "text_color" => "#FFFFFF",
           "bg_color" => "#000000",
           "bg_opacity" => 0.75,
           "subject" => "A stunning space image",
           "rotation" => "none"
         }}
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

      # --- Step 2: ExtractPageWorker (re-fetches the URL) ---
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
      assert length(all_enqueued(worker: DownloadImageWorker)) == 2

      # --- Steps 3-7: Item pipeline for each item ---
      for item <- items do
        # DownloadImageWorker: HTTP get from original_url + Storage upload
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{"content-type" => ["image/jpeg"]}}}
        end)

        assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "thumbnail"

        # ThumbnailWorker: HTTP get from MinIO storage URL + Storage upload
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)

        assert :ok = perform_job(ThumbnailWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "analyze"

        # AnalyzeWorker: HTTP get from MinIO original URL + Gemini image call (analysis + rotation)
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)

        assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "resize"

        # ResizeWorker: HTTP get from MinIO original URL + Storage upload
        expect(MockHttp, :get, fn _url, _opts ->
          {:ok, %{status: 200, body: @test_jpeg, headers: %{}}}
        end)

        assert :ok = perform_job(ResizeWorker, %{item_id: item.id})
        assert Catalog.get_item!(item.id).status == "render"

        # RenderWorker: HTTP get from MinIO processed URL + Storage upload
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

      assert :ok =
               perform_job(
                 ExtractPageWorker,
                 %{source_id: source.id, url: "#{@source_url}?page=2"}
               )

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
             end),
             "All items must have absolute image_url"

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
