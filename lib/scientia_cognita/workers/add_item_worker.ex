defmodule ScientiaCognita.Workers.AddItemWorker do
  @moduledoc """
  Oban worker that adds a single catalog item to an existing Google Photos album.

  Flow:
    1. Load export, item, and user. Verify the export belongs to the requesting user.
    2. If the album does not yet exist (rare edge-case), create it.
    3. Upload the item's bytes to get an upload token.
    4. batchCreate the single media item in the album.
    5. Mark the item as uploaded with its Google Photos media ID.
    6. Broadcast :item_added on the export PubSub topic.
    7. On any error: mark the item as failed and broadcast :item_add_failed.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Photos}
  alias ScientiaCognita.Photos.GoogleErrors
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"export_id" => export_id, "item_id" => item_id, "user_id" => user_id}
      }) do
    export = Photos.get_export!(export_id)
    item = Catalog.get_item!(item_id)
    user = Accounts.get_user!(user_id)

    if export.user_id != user_id do
      {:error, :unauthorized}
    else
      do_add_item(export, item, user, user_id)
    end
  rescue
    e ->
      friendly = GoogleErrors.translate(Exception.message(e))

      try do
        export = Photos.get_export!(export_id)
        item = Catalog.get_item!(item_id)
        Photos.set_item_failed(export, item, friendly)

        Phoenix.PubSub.broadcast(
          ScientiaCognita.PubSub,
          "export:#{export.catalog_id}:#{user_id}",
          {:item_add_failed, %{item_id: item_id, error: friendly}}
        )
      rescue
        _ -> :ok
      end

      reraise e, __STACKTRACE__
  end

  defp do_add_item(export, item, user, user_id) do
    token = user.google_access_token
    topic = "export:#{export.catalog_id}:#{user_id}"

    # Create album if it doesn't exist yet (e.g. export was never run to completion)
    export =
      if is_nil(export.album_id) do
        catalog = Catalog.get_catalog!(export.catalog_id)
        {:ok, album_id, album_url} = create_album!(token, catalog.name)
        {:ok, export} = Photos.set_export_status(export, export.status, album_id: album_id, album_url: album_url)
        export
      else
        export
      end

    {:ok, image_binary} = fetch_image(item)
    {:ok, upload_token} = upload_bytes(token, image_binary, item.title)
    {:ok, token_to_media_id} = batch_add_items(token, export.album_id, [{item, upload_token}])
    media_id = Map.get(token_to_media_id, upload_token)

    Photos.set_item_uploaded(export, item, media_id)

    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {:item_added, %{item_id: item.id}})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Google Photos API helpers (shared with ExportAlbumWorker)
  # ---------------------------------------------------------------------------

  defp create_album!(token, name) do
    response =
      Req.post!(
        "#{@photos_base}/albums",
        json: %{album: %{title: name}},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> {:ok, response.body["id"], response.body["productUrl"]}
      status -> raise "Failed to create album: HTTP #{status} — #{inspect(response.body)}"
    end
  end

  defp fetch_image(item) do
    url = ItemImageUploader.url({item.final_image, item})

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "fetch failed HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, "fetch error: #{inspect(reason)}"}
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
          {"X-Goog-Upload-File-Name", "#{sanitize_filename(filename)}.jpg"}
        ]
      )

    case response.status do
      200 -> {:ok, response.body}
      _ -> {:error, "HTTP #{response.status}: #{inspect(response.body)}"}
    end
  end

  defp batch_add_items(token, album_id, items_with_tokens) do
    new_media_items =
      Enum.map(items_with_tokens, fn {item, upload_token} ->
        %{
          description: item.title,
          simpleMediaItem: %{
            fileName: "#{sanitize_filename(item.title)}.jpg",
            uploadToken: upload_token
          }
        }
      end)

    response =
      Req.post!(
        "#{@photos_base}/mediaItems:batchCreate",
        json: %{albumId: album_id, newMediaItems: new_media_items},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 ->
        results = response.body["newMediaItemResults"] || []

        token_to_media_id =
          Map.new(results, fn r ->
            {r["uploadToken"], get_in(r, ["mediaItem", "id"])}
          end)

        {:ok, token_to_media_id}

      status ->
        raise "batchCreate failed with HTTP #{status}: #{inspect(response.body)}"
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.to_charlist()
    |> Enum.filter(&(&1 >= 0x20 and &1 <= 0x7E))
    |> List.to_string()
    |> String.trim()
  end
end
