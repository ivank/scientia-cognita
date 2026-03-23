defmodule ScientiaCognita.Workers.ExportAlbumWorker do
  @moduledoc """
  Oban worker that exports (or syncs) a catalog to a Google Photos album.

  Flow:
    1. Upsert a PhotoExport record and set status: running.
    2. Create the Google Photos album if album_id is nil.
    3. Determine which items are not yet uploaded (incremental sync).
    4. Upload each new item's bytes to get an upload token. Record failures.
    5. Batch-create media items in the album (50 per call).
       After each successful batch, mark those items as uploaded in the DB.
    6. Set export status: done, persist album_url, broadcast done.
    7. On crash: set export status: failed, broadcast failed.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Photos}
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"catalog_id" => catalog_id, "user_id" => user_id}}) do
    catalog = Catalog.get_catalog!(catalog_id)
    user = Accounts.get_user!(user_id)
    all_items = Catalog.list_catalog_items(catalog)
    token = user.google_access_token
    topic = "export:#{catalog_id}:#{user_id}"

    # 1. Upsert export and mark running
    {:ok, export} = Photos.get_or_create_export(user, catalog)
    {:ok, export} = Photos.set_export_status(export, "running")

    # 2. Create album in Google Photos if this is the first run
    export =
      if is_nil(export.album_id) do
        {:ok, album_id, album_url} = create_album!(token, catalog.name)
        {:ok, export} = Photos.set_export_status(export, "running", album_id: album_id, album_url: album_url)
        export
      else
        export
      end

    # 3. Skip already-uploaded items (incremental sync)
    already_uploaded_ids = Photos.list_uploaded_item_ids(export)

    items_to_upload =
      all_items
      |> Enum.filter(& &1.final_image)
      |> Enum.reject(&(&1.id in already_uploaded_ids))

    total = length(items_to_upload)

    # 4. Upload bytes and collect {item, upload_token} pairs.
    # Items are prepended (reversed at step 5) for O(1) accumulation.
    {successful_pairs, _} =
      items_to_upload
      |> Enum.with_index(1)
      |> Enum.reduce({[], 0}, fn {item, idx}, {acc, _} ->
        fetch_result = fetch_image(item)

        case fetch_result do
          {:error, reason} ->
            {:ok, _} = Photos.set_item_failed(export, item, reason)
            {acc, idx}

          {:ok, image_binary} ->
            case upload_bytes(token, image_binary, item.title) do
              {:ok, upload_token} ->
                Phoenix.PubSub.broadcast(
                  ScientiaCognita.PubSub,
                  topic,
                  {:export_progress, %{uploaded: idx, total: total}}
                )

                {[{item, upload_token} | acc], idx}

              {:error, reason} ->
                {:ok, _} = Photos.set_item_failed(export, item, reason)
                {acc, idx}
            end
        end
      end)

    # 5. Batch-create media items, mark each batch as uploaded in DB after confirmed success
    successful_pairs
    |> Enum.reverse()
    |> Enum.chunk_every(50)
    |> Enum.each(fn chunk ->
      # NOTE: batch_add_items raises on non-200; if it raises, the rescue block
      # catches it. Items in the failed batch stay pending and will retry on next sync.
      :ok = batch_add_items(token, export.album_id, chunk)

      Enum.each(chunk, fn {item, _token} ->
        Photos.set_item_uploaded(export, item)
      end)
    end)

    # 6. Mark done, broadcast
    {:ok, _} = Photos.set_export_status(export, "done")

    Phoenix.PubSub.broadcast(
      ScientiaCognita.PubSub,
      topic,
      {:export_done, %{album_url: export.album_url}}
    )

    :ok
  rescue
    e ->
      # catalog_id and user_id are local variables from the function head — use them directly.
      # Do NOT use Map.get(e, :catalog_id) — exception structs don't carry job args.
      try do
        if export = Photos.get_export_for_user(
             Accounts.get_user!(user_id),
             Catalog.get_catalog!(catalog_id)
           ) do
          Photos.set_export_status(export, "failed", error: Exception.message(e))
        end
      rescue
        _ -> :ok
      end

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        "export:#{catalog_id}:#{user_id}",
        {:export_failed, Exception.message(e)}
      )

      reraise e, __STACKTRACE__
  end

  # ---------------------------------------------------------------------------
  # Google Photos API helpers
  # ---------------------------------------------------------------------------

  # Raises on failure so the job fails fast with a clear error message in the rescue block.
  defp create_album!(token, name) do
    response =
      Req.post!(
        "#{@photos_base}/albums",
        json: %{album: %{title: name}},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> {:ok, response.body["id"], response.body["productUrl"]}
      status -> raise "Failed to create Google Photos album: HTTP #{status} — #{inspect(response.body)}"
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
      _ -> {:error, "HTTP #{response.status}: #{inspect(response.body)}"}
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

    response =
      Req.post!(
        "#{@photos_base}/mediaItems:batchCreate",
        json: %{albumId: album_id, newMediaItems: new_media_items},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 -> :ok
      status -> raise "batchCreate failed with HTTP #{status}: #{inspect(response.body)}"
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
end
