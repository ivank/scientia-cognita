defmodule ScientiaCognita.Workers.FetchPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp}
  alias ScientiaCognita.Workers.{FetchPageWorker, ExtractPageWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "fetches HTML, saves raw_html, transitions to extracting, enqueues ExtractPageWorker" do
      source = source_fixture(%{status: "pending"})
      html = "<html><body>gallery content</body></html>"

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: html, headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.raw_html == html

      assert_enqueued(
        worker: ExtractPageWorker,
        args: %{"source_id" => source.id, "url" => source.url}
      )
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks source as failed on HTTP error" do
      source = source_fixture(%{status: "pending"})

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
      assert source.error =~ "timeout"
    end
  end

  describe "perform/1 — non-200 response" do
    test "marks source as failed on non-200 HTTP status" do
      source = source_fixture(%{status: "pending"})

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 404, body: "Not Found", headers: %{}}}
      end)

      assert :ok = perform_job(FetchPageWorker, %{source_id: source.id})

      source = Catalog.get_source!(source.id)
      assert source.status == "failed"
    end
  end
end
