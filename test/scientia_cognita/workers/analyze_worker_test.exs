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

  describe "perform/1 — happy path" do
    test "downloads thumbnail, calls Gemini, saves image_analysis, transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", thumbnail_image: "thumbnail.jpg"})

      expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/thumbnail.jpg" end)

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

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — Gemini fallback" do
    test "uses default analysis when Gemini fails, still transitions to resize" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", thumbnail_image: "thumbnail.jpg"})

      expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/thumbnail.jpg" end)

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
      # Default fallback values
      assert item.image_analysis["text_color"] == "#FFFFFF"
      assert item.image_analysis["bg_color"] == "#000000"
      assert item.image_analysis["bg_opacity"] == 0.75

      assert_enqueued(worker: ResizeWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks item as failed when thumbnail download fails" do
      source = source_fixture()
      item = item_fixture(source, %{status: "analyze", thumbnail_image: "thumbnail.jpg"})

      expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/thumbnail.jpg" end)
      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(AnalyzeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
      assert item.error =~ "timeout"
    end
  end
end
