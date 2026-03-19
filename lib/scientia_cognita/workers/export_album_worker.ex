defmodule ScientiaCognita.Workers.ExportAlbumWorker do
  @moduledoc """
  Oban worker that exports a catalog to a Google Photos album.

  Flow:
    1. Create a new album in Google Photos with the catalog name.
    2. For each item with a processed image, upload the bytes and collect upload tokens.
    3. Batch-create media items in the album.
    4. Broadcast progress and final album URL over PubSub.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Storage}

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"catalog_id" => catalog_id, "user_id" => user_id}}) do
    catalog = Catalog.get_catalog!(catalog_id)
    user = Accounts.get_user!(user_id)
    items = Catalog.list_catalog_items(catalog)
    topic = "export:#{catalog_id}"

    token = user.google_access_token

    # 1. Create album
    {:ok, album_id} = create_album(token, catalog.name)

    # 2. Upload images and gather tokens
    total = Enum.count(items, & &1.processed_key)

    upload_tokens =
      items
      |> Enum.filter(& &1.processed_key)
      |> Enum.with_index(1)
      |> Enum.map(fn {item, idx} ->
        image_binary = fetch_image(item.processed_key)
        {:ok, upload_token} = upload_bytes(token, image_binary, item.title)
        Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {:export_progress, %{uploaded: idx, total: total}})
        {item, upload_token}
      end)

    # 3. Batch create media items (Google Photos allows up to 50 per call)
    upload_tokens
    |> Enum.chunk_every(50)
    |> Enum.each(fn chunk ->
      batch_add_items(token, album_id, chunk)
    end)

    # 4. Build shareable link
    album_url = "https://photos.google.com/album/#{album_id}"
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {:export_done, %{album_url: album_url}})

    :ok
  rescue
    e ->
      topic = "export:#{Map.get(e, :catalog_id, "unknown")}"
      Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {:export_failed, inspect(e)})
      reraise e, __STACKTRACE__
  end

  # ---------------------------------------------------------------------------
  # Google Photos API helpers
  # ---------------------------------------------------------------------------

  defp create_album(token, name) do
    response =
      Req.post!(
        "#{@photos_base}/albums",
        json: %{album: %{title: name}},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> {:ok, response.body["id"]}
      _ -> {:error, response.body}
    end
  end

  defp upload_bytes(token, binary, filename) do
    response =
      Req.post!(
        "#{@photos_base}/uploads",
        body: binary,
        headers: [
          {"Authorization", "Bearer #{token}"},
          {"Content-type", "application/octet-stream"},
          {"X-Goog-Upload-Protocol", "raw"},
          {"X-Goog-Upload-File-Name", "#{filename}.jpg"}
        ]
      )

    case response.status do
      200 -> {:ok, response.body}
      _ -> {:error, response.body}
    end
  end

  defp batch_add_items(token, album_id, items_with_tokens) do
    new_media_items =
      Enum.map(items_with_tokens, fn {item, upload_token} ->
        %{
          description: item.title,
          simpleMediaItem: %{
            fileName: "#{item.title}.jpg",
            uploadToken: upload_token
          }
        }
      end)

    Req.post!(
      "#{@photos_base}/mediaItems:batchCreate",
      json: %{albumId: album_id, newMediaItems: new_media_items},
      headers: [{"Authorization", "Bearer #{token}"}]
    )
  end

  defp fetch_image(processed_key) do
    url = Storage.get_url(processed_key)
    response = Req.get!(url)
    response.body
  end
end
