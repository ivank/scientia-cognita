defmodule ScientiaCognita.Workers.ProcessImageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockStorage}
  alias ScientiaCognita.Workers.{ProcessImageWorker, ColorAnalysisWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads original, resizes to 1920x1080, uploads processed, transitions to color_analysis" do
      source = source_fixture()
      item = item_fixture(source, %{status: "processing", storage_key: "items/1/original.jpg"})

      # Mock: download original from MinIO
      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      # Mock: upload processed image
      expect(MockStorage, :upload, fn key, _binary, _opts ->
        assert key =~ "processed"
        {:ok, %{}}
      end)

      assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "color_analysis"
      assert item.processed_key != nil

      assert_enqueued(worker: ColorAnalysisWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks item as failed when original image download fails" do
      source = source_fixture()
      item = item_fixture(source, %{status: "processing", storage_key: "items/1/original.jpg"})

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(ProcessImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
      assert item.error =~ "timeout"
    end
  end
end
