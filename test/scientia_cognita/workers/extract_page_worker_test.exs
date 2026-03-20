defmodule ScientiaCognita.Workers.ExtractPageWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp}
  alias ScientiaCognita.Workers.{ExtractPageWorker, DownloadImageWorker}

  setup :verify_on_exit!

  @fixture_html File.read!("test/fixtures/gallery_page.html")

  @selectors %{
    selector_title: ".item-title",
    selector_image: ".item img",
    selector_description: ".item-desc",
    selector_copyright: ".credit",
    selector_next_page: "a.next-page"
  }

  describe "perform/1 — page with items and next page" do
    test "extracts items, enqueues download workers, follows pagination" do
      source = analyzed_source_fixture(@selectors)

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: @fixture_html, headers: %{}}}
      end)

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      items = Catalog.list_items_by_source(source)
      assert length(items) == 2
      assert Enum.any?(items, &(&1.title == "Orion Nebula"))
      assert Enum.any?(items, &(&1.title == "Andromeda Galaxy"))

      # Item download workers enqueued
      assert_enqueued worker: DownloadImageWorker

      # Self-loop for next page
      assert_enqueued worker: ExtractPageWorker,
                      args: %{
                        "source_id" => source.id,
                        "url" => "https://example.com/gallery?page=2"
                      }

      source = Catalog.get_source!(source.id)
      assert source.status == "extracting"
      assert source.pages_fetched == 1
      assert source.next_page_url == "https://example.com/gallery?page=2"
    end
  end

  describe "perform/1 — last page (no next)" do
    test "transitions source to done when no next page selector matches" do
      html_no_next = String.replace(@fixture_html, ~r/<a class="next-page".*?<\/a>/s, "")

      source = analyzed_source_fixture(Map.merge(@selectors, %{selector_next_page: "a.next-page"}))

      expect(MockHttp, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: html_no_next, headers: %{}}}
      end)

      assert :ok =
               perform_job(ExtractPageWorker, %{
                 source_id: source.id,
                 url: "https://example.com/gallery"
               })

      source = Catalog.get_source!(source.id)
      assert source.status == "done"
    end
  end
end
