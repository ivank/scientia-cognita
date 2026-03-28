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
    test "calls analysis-only Gemini, sets rotation: none, transitions to resize" do
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

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Portrait image — combined Gemini call, rotation: none
  # ---------------------------------------------------------------------------

  describe "perform/1 — portrait image, Gemini says none" do
    test "keeps original, stores rotation: none, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      # Portrait JPEG (56×100)
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
      # no re-upload — original_image filename unchanged
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Portrait image — combined Gemini call, rotation: clockwise
  # ---------------------------------------------------------------------------

  describe "perform/1 — portrait image, Gemini says clockwise" do
    test "rotates, re-uploads original, stores rotation: clockwise, transitions to resize" do
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

      expect(MockUploader, :store, fn {%{filename: "original.jpg"}, _item} ->
        {:ok, "original.jpg"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "clockwise"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  # ---------------------------------------------------------------------------
  # Portrait image — combined Gemini call, rotation: counterclockwise
  # ---------------------------------------------------------------------------

  describe "perform/1 — portrait image, Gemini says counterclockwise" do
    test "rotates counterclockwise, re-uploads, stores rotation: counterclockwise" do
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

      expect(MockUploader, :store, fn {%{filename: "original.jpg"}, _item} ->
        {:ok, "original.jpg"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "counterclockwise"

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
  # Manual rotation override
  # ---------------------------------------------------------------------------

  describe "perform/1 — manual_rotation set" do
    test "uses analysis-only Gemini call and applies manual rotation (clockwise)" do
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

      # Portrait image so we can verify rotation is applied
      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      # Must call analysis-only schema (no rotation field in response)
      expect(MockGemini, :generate_structured_with_image, fn _prompt, _binary, _schema, _opts ->
        {:ok, @analysis_result}
      end)

      expect(MockUploader, :store, fn {%{filename: "original.jpg"}, _item} ->
        {:ok, "original.jpg"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "clockwise"
      assert item.image_analysis["text_color"] == "#FFFFFF"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end

    test "uses manual rotation none without rotating, even for portrait image" do
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

      # No uploader store call — original is kept as-is
      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      assert item.image_analysis["rotation"] == "none"
      assert item.original_image.file_name == "original.jpg"

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end

    test "uses manual rotation even when Gemini fails" do
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

      expect(MockUploader, :store, fn {%{filename: "original.jpg"}, _item} ->
        {:ok, "original.jpg"}
      end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "resize"
      # rotation still applied from manual_rotation despite Gemini failure
      assert item.image_analysis["rotation"] == "counterclockwise"
      # analysis falls back to defaults
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
