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
