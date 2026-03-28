defmodule ScientiaCognita.Workers.RenderWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
  alias ScientiaCognita.Workers.RenderWorker

  setup :verify_on_exit!

  @analysis %{
    "text_color" => "#FFFFFF",
    "bg_color" => "#1A1A2E",
    "bg_opacity" => 0.75,
    "subject" => "Orion Nebula"
  }

  describe "perform/1 — happy path" do
    test "downloads processed image, renders text overlay, uploads final, marks ready" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "render",
          title: "Orion Nebula",
          description: "A stellar nursery",
          processed_image: "processed.jpg",
          image_analysis: @analysis
        })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/processed.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

      assert :ok = perform_job(RenderWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "ready"
      assert item.final_image != nil
    end
  end

  describe "perform/1 — uses default colors when item has no image_analysis" do
    test "renders with fallback colors if image_analysis is nil" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "render",
          processed_image: "processed.jpg"
          # image_analysis is nil
        })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/processed.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts -> {:ok, %{status: 200, body: jpeg, headers: %{}}} end)

      expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

      assert :ok = perform_job(RenderWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "ready"
    end
  end

  describe "perform/1 — source completion" do
    test "transitions source to done when last item finishes" do
      source = source_fixture(%{status: "items_loading"})

      item =
        item_fixture(source, %{
          status: "render",
          processed_image: "processed.jpg",
          image_analysis: @analysis
        })

      jpeg = File.read!("test/fixtures/test_image.jpg")

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/processed.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts -> {:ok, %{status: 200, body: jpeg, headers: %{}}} end)

      expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "final.jpg"} end)

      assert :ok = perform_job(RenderWorker, %{item_id: item.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "done"
    end
  end
end
