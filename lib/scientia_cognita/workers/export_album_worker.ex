defmodule ScientiaCognita.Workers.ExportAlbumWorker do
  @moduledoc """
  Oban worker that exports (or syncs) a catalog to a Google Photos album.

  Flow:
    1. Upsert a PhotoExport record and set status: running.
    2. Create the Google Photos album if album_id is nil.
    3. Determine which items to upload (all non-uploaded, or a specific subset via
       the optional `item_ids` job arg — used for targeted retry / new-only sync).
    4. Upload each item's bytes to get an upload token. Before each item, check
       whether the export has been cancelled (DB flag). Record per-item failures
       without stopping; broadcast progress and per-item failure events.
    5. If not cancelled: batch-create media items in the album (50 per call).
       After each successful batch, mark those items as uploaded in the DB.
    6. If not cancelled: set export status: done, broadcast done.
    7. On crash: set export status: failed, broadcast failed.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Photos}
  alias ScientiaCognita.Photos.GoogleErrors
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"catalog_id" => catalog_id, "user_id" => user_id} = args}) do
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

        {:ok, export} =
          Photos.set_export_status(export, "running", album_id: album_id, album_url: album_url)

        export
      else
        export
      end

    # 3. Determine which items to upload.
    #    - Always skip already-uploaded items.
    #    - If `item_ids` is provided, restrict to that subset (targeted retry / new-only sync).
    already_uploaded_ids = MapSet.new(Photos.list_uploaded_item_ids(export))

    base_items =
      all_items
      |> Enum.filter(& &1.final_image)
      |> Enum.reject(&MapSet.member?(already_uploaded_ids, &1.id))

    items_to_upload =
      case Map.get(args, "item_ids") do
        nil -> base_items
        ids -> Enum.filter(base_items, &(&1.id in ids))
      end

    total = length(items_to_upload)

    # 4. Upload bytes and collect {item, upload_token} pairs.
    #    Before each item, check whether the user cancelled (DB flag).
    #    Each failure is recorded per-item and broadcast; the loop always continues
    #    unless cancelled.
    #    Accumulator: {reversed_success_pairs, uploaded_count, failed_count}
    {successful_pairs_reversed, _uploaded, _failed} =
      Enum.reduce_while(items_to_upload, {[], 0, 0}, fn item, {acc, uploaded, failed} ->
        if Photos.reload_export(export).status == "cancelled" do
          {:halt, {acc, uploaded, failed}}
        else
          result =
            case fetch_image(item) do
              {:error, reason} ->
                {:ok, _} = Photos.set_item_failed(export, item, reason)

                Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {
                  :export_item_failed,
                  %{item_id: item.id, title: item.title, error: to_string(reason)}
                })

                Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {
                  :export_progress,
                  %{uploaded: uploaded, failed: failed + 1, total: total}
                })

                {acc, uploaded, failed + 1}

              {:ok, image_binary} ->
                case upload_bytes(token, image_binary, item.title) do
                  {:ok, upload_token} ->
                    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {
                      :export_progress,
                      %{uploaded: uploaded + 1, failed: failed, total: total}
                    })

                    {[{item, upload_token} | acc], uploaded + 1, failed}

                  {:error, raw_reason} ->
                    friendly = GoogleErrors.translate(to_string(raw_reason))
                    {:ok, _} = Photos.set_item_failed(export, item, friendly)

                    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {
                      :export_item_failed,
                      %{item_id: item.id, title: item.title, error: friendly}
                    })

                    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {
                      :export_progress,
                      %{uploaded: uploaded, failed: failed + 1, total: total}
                    })

                    {acc, uploaded, failed + 1}
                end
            end

          {:cont, result}
        end
      end)

    # 5 & 6. If not cancelled: batch-create and mark done.
    unless Photos.reload_export(export).status == "cancelled" do
      successful_pairs_reversed
      |> Enum.reverse()
      |> Enum.chunk_every(50)
      |> Enum.each(fn chunk ->
        # NOTE: batch_add_items raises on non-200; if it raises, the rescue block
        # catches it. Items in the failed batch stay pending and will retry on next sync.
        {:ok, token_to_media_id} = batch_add_items(token, export.album_id, chunk)

        Enum.each(chunk, fn {item, upload_token} ->
          media_id = Map.get(token_to_media_id, upload_token)
          Photos.set_item_uploaded(export, item, media_id)
        end)
      end)

      {:ok, done_export} = Photos.set_export_status(export, "done")

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        topic,
        {:export_done, %{album_url: done_export.album_url}}
      )
    end

    :ok
  rescue
    e ->
      # catalog_id and user_id are local variables from the function head — use them directly.
      # Do NOT use Map.get(e, :catalog_id) — exception structs don't carry job args.
      friendly = GoogleErrors.translate(Exception.message(e))

      try do
        if export =
             Photos.get_export_for_user(
               Accounts.get_user!(user_id),
               Catalog.get_catalog!(catalog_id)
             ) do
          Photos.set_export_status(export, "failed", error: friendly)
        end
      rescue
        _ -> :ok
      end

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        "export:#{catalog_id}:#{user_id}",
        {:export_failed, friendly}
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
      200 ->
        {:ok, response.body["id"], response.body["productUrl"]}

      status ->
        raise "Failed to create Google Photos album: HTTP #{status} — #{inspect(response.body)}"
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

  # Strip non-printable-ASCII characters so the filename is safe for HTTP headers.
  # This handles Unicode characters like curly quotes (e.g. "Syrup's sharp edges").
  defp sanitize_filename(name) do
    name
    |> String.to_charlist()
    |> Enum.filter(&(&1 >= 0x20 and &1 <= 0x7E))
    |> List.to_string()
    |> String.trim()
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
            media_id = get_in(r, ["mediaItem", "id"])
            {r["uploadToken"], media_id}
          end)

        {:ok, token_to_media_id}

      status ->
        raise "batchCreate failed with HTTP #{status}: #{inspect(response.body)}"
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
