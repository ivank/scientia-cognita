defmodule ScientiaCognita.Workers.AnalyzeWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockGemini, MockUploader}
  alias ScientiaCognita.Workers.{AnalyzeWorker, ResizeWorker}

  setup :verify_on_exit!

  @analysis_result %{
    "text_color" => "#FFFFFF",
    "bg_color" => "#1A1A2E",
    "bg_opacity" => 0.75,
    "subject" => "A spiral galaxy with bright core"
  }

  @combined_result %{
    "text_color" => "#FFFFFF",
    "bg_color" => "#1A1A2E",
    "bg_opacity" => 0.75,
    "subject" => "A spiral galaxy with bright core",
    "rotation" => "none"
  }

  # ---------------------------------------------------------------------------
  # Landscape image — analysis only, rotation set to "none" without Gemini
  # ---------------------------------------------------------------------------

  describe "perform/1 — landscape image" do
    test "calls analysis-only Gemini, stores rotation: none, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      # Landscape JPEG (100×56)
      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, @analysis_result}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["text_color"] == "#FFFFFF"
      assert item.image_analysis["bg_color"] == "#1A1A2E"
      assert item.image_analysis["subject"] == "A spiral galaxy with bright core"
      assert item.image_analysis["rotation"] == "none"
      # original_image untouched — rotation applied later in ResizeWorker
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Portrait image — combined Gemini call
  # AnalyzeWorker only STORES the rotation decision; ResizeWorker applies it.
  # ---------------------------------------------------------------------------

  describe "perform/1 — portrait image, Gemini says none" do
    test "stores rotation: none, original_image untouched, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, @combined_result}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "none"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — portrait image, Gemini says clockwise" do
    test "stores rotation: clockwise, original_image untouched, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, Map.put(@combined_result, "rotation", "clockwise")}
      end)

      # No MockUploader.store — rotation is applied by ResizeWorker, not here
      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "clockwise"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — portrait image, Gemini says counterclockwise" do
    test "stores rotation: counterclockwise, original_image untouched, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, Map.put(@combined_result, "rotation", "counterclockwise")}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "counterclockwise"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Gemini failure — defaults applied, still transitions to resize
  # ---------------------------------------------------------------------------

  describe "perform/1 — Gemini failure" do
    test "uses default analysis, sets rotation: none, still transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["text_color"] == "#FFFFFF"
      assert item.image_analysis["bg_color"] == "#000000"
      assert item.image_analysis["bg_opacity"] == 0.75
      assert item.image_analysis["rotation"] == "none"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Manual rotation override — stores the override, no upload
  # ---------------------------------------------------------------------------

  describe "perform/1 — manual_rotation set" do
    test "stores manual rotation (clockwise), analysis-only Gemini call, no upload" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "analyze",
          original_image: "original.jpg",
          manual_rotation: "clockwise"
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, @analysis_result}
      end)

      # No MockUploader.store — rotation is applied by ResizeWorker
      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "clockwise"
      assert item.image_analysis["text_color"] == "#FFFFFF"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end

    test "stores manual rotation none, even for portrait image" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "analyze",
          original_image: "original.jpg",
          manual_rotation: "none"
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, @analysis_result}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "none"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end

    test "stores manual rotation even when Gemini fails" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "analyze",
          original_image: "original.jpg",
          manual_rotation: "counterclockwise"
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:error, "API quota exceeded"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "counterclockwise"
      assert item.image_analysis["text_color"] == "#FFFFFF"
      assert item.image_analysis["bg_color"] == "#000000"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP error
  # ---------------------------------------------------------------------------

  describe "perform/1 — HTTP error" do
    test "marks item as failed when original download fails" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
      assert item.error =~ "timeout"
    end
  end
end
