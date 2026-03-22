defmodule ScientiaCognita.Workers.ThumbnailWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
  alias ScientiaCognita.Workers.{ThumbnailWorker, AnalyzeWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads original, generates thumbnail, uploads, transitions to analyze, enqueues AnalyzeWorker" do
      source = source_fixture()
      item = item_fixture(source, %{status: "thumbnail", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/original.jpg" end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockUploader, :store, fn {%{filename: "thumbnail.jpg"}, _item} -> {:ok, "thumbnail.jpg"} end)

      assert :ok = perform_job(ThumbnailWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "analyze"
      assert item.thumbnail_image != nil

      assert_enqueued(worker: AnalyzeWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks item as failed when original image download fails" do
      source = source_fixture()
      item = item_fixture(source, %{status: "thumbnail", original_image: "original.jpg"})

      expect(MockUploader, :url, fn _ -> "http://localhost:9000/images/items/#{item.id}/original.jpg" end)
      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(ThumbnailWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
      assert item.error =~ "timeout"
    end
  end
end
