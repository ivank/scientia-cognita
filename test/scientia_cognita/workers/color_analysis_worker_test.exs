defmodule ScientiaCognita.Workers.ColorAnalysisWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockGemini}
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
