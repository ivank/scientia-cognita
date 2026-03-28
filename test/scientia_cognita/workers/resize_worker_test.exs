defmodule ScientiaCognita.Workers.ResizeWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import Mox
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.{Catalog, MockHttp, MockUploader}
  alias ScientiaCognita.Workers.{ResizeWorker, RenderWorker}

  setup :verify_on_exit!

  describe "perform/1 — happy path" do
    test "downloads original, resizes to 1920x1080, uploads processed, transitions to render" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "resize",
          original_image: "original.jpg",
          image_analysis: %{
            "text_color" => "#FFFFFF",
            "bg_color" => "#000000",
            "bg_opacity" => 0.75,
            "subject" => "Orion Nebula"
          }
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockUploader, :store, fn {%{filename: "processed.jpg"}, _item} ->
        {:ok, "processed.jpg"}
      end)

      assert :ok = perform_job(ResizeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "render"
      assert item.processed_image != nil

      assert_enqueued(worker: RenderWorker, args: %{"item_id" => item.id})
    end
  end

  describe "perform/1 — rotation applied before resize" do
    test "rotates portrait image clockwise before resizing" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "resize",
          original_image: "original.jpg",
          image_analysis: %{
            "text_color" => "#FFFFFF",
            "bg_color" => "#000000",
            "bg_opacity" => 0.75,
            "subject" => "A gecko foot",
            "rotation" => "clockwise"
          }
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      # Portrait image (56×100) — rotation makes it landscape before the crop
      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockUploader, :store, fn {%{filename: "processed.jpg"}, _item} ->
        {:ok, "processed.jpg"}
      end)

      assert :ok = perform_job(ResizeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "render"
      assert item.processed_image != nil

      assert_enqueued(worker: RenderWorker, args: %{"item_id" => item.id})
    end

    test "rotates portrait image counterclockwise before resizing" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "resize",
          original_image: "original.jpg",
          image_analysis: %{
            "text_color" => "#FFFFFF",
            "bg_color" => "#000000",
            "bg_opacity" => 0.75,
            "subject" => "A nebula",
            "rotation" => "counterclockwise"
          }
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts ->
        jpeg = File.read!("test/fixtures/test_image_portrait.jpg")
        {:ok, %{status: 200, body: jpeg, headers: %{}}}
      end)

      expect(MockUploader, :store, fn {%{filename: "processed.jpg"}, _item} ->
        {:ok, "processed.jpg"}
      end)

      assert :ok = perform_job(ResizeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "render"
      assert item.processed_image != nil
    end
  end

  describe "perform/1 — HTTP error" do
    test "marks item as failed when original image download fails" do
      source = source_fixture()

      item =
        item_fixture(source, %{
          status: "resize",
          original_image: "original.jpg"
        })

      expect(MockUploader, :url, fn _ ->
        "http://localhost:9000/images/items/#{item.id}/original.jpg"
      end)

      expect(MockHttp, :get, fn _url, _opts -> {:error, :timeout} end)

      assert :ok = perform_job(ResizeWorker, %{item_id: item.id})

      item = Catalog.get_item!(item.id)
      assert item.status == "failed"
      assert item.error =~ "timeout"
    end
  end
end
