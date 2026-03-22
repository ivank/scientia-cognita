defmodule ScientiaCognita.Workers.DownloadImageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
  alias ScientiaCognita.Workers.{DownloadImageWorker, ProcessImageWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads image, uploads via uploader, transitions to processing, enqueues ProcessImageWorker" do
      source = source_fixture()
      item = item_fixture(source, %{original_url: "https://example.com/image.jpg"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok,
         %{status: 200, body: <<255, 216, 255>>, headers: %{"content-type" => ["image/jpeg"]}}}
      end)

      expect(MockUploader, :store, fn {_upload, _item} -> {:ok, "original.jpg"} end)

      assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "processing"
      assert item.original_image != nil

      assert_enqueued(worker: ProcessImageWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks item as failed on download error" do
      source = source_fixture()
      item = item_fixture(source, %{original_url: "https://example.com/image.jpg"})

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(DownloadImageWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
    end
  end
end
