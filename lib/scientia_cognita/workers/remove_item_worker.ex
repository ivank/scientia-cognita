defmodule ScientiaCognita.Workers.RemoveItemWorker do
  @moduledoc """
  Oban worker that removes a single item from a Google Photos album.

  Flow:
    1. Load export, item, and user. Verify the export belongs to the requesting user.
    2. Look up the Google Photos media ID from the PhotoExportItem record.
       If missing (item was exported before media-ID tracking was added), search
       the album by filename to find the ID.
    3. Call albums:batchRemoveMediaItems to remove it from the album.
       If no media ID can be found, skip the API call (item may already be gone).
    4. Delete the PhotoExportItem record.
    5. Broadcast :item_removed on the export PubSub topic.
    6. On error: restore the item's status to "uploaded" and broadcast :item_remove_failed.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  alias ScientiaCognita.{Catalog, Accounts, Photos}
  alias ScientiaCognita.Photos.GoogleErrors

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
      do_remove_item(export, item, user, user_id)
    end
  rescue
    e ->
      friendly = GoogleErrors.translate(Exception.message(e))

      try do
        export = Photos.get_export!(export_id)
        item = Catalog.get_item!(item_id)
        # Restore to uploaded so the user can retry
        Photos.set_item_uploaded(export, item)

        Phoenix.PubSub.broadcast(
          ScientiaCognita.PubSub,
          "export:#{export.catalog_id}:#{user_id}",
          {:item_remove_failed, %{item_id: item_id, error: friendly}}
        )
      rescue
        _ -> :ok
      end

      reraise e, __STACKTRACE__
  end

  defp do_remove_item(export, item, user, user_id) do
    token = user.google_access_token
    topic = "export:#{export.catalog_id}:#{user_id}"

    # Resolve the Google Photos media ID
    media_id =
      case Photos.get_export_item(export, item) do
        nil -> nil
        %{google_photos_media_id: id} when not is_nil(id) -> id
        _ -> search_album_for_item(token, export.album_id, item)
      end

    # Remove from Google Photos album (best-effort — skip if we have no media ID)
    if media_id && export.album_id do
      remove_from_album!(token, export.album_id, media_id)
    end

    Photos.delete_export_item(export, item)

    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, topic, {:item_removed, %{item_id: item.id}})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Google Photos API helpers
  # ---------------------------------------------------------------------------

  defp remove_from_album!(token, album_id, media_id) do
    response =
      Req.post!(
        "#{@photos_base}/albums/#{album_id}:batchRemoveMediaItems",
        json: %{mediaItemIds: [media_id]},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 ->
        :ok

      status ->
        raise "batchRemoveMediaItems failed: HTTP #{status} — #{inspect(response.body)}"
    end
  end

  # Searches the album for an item with matching filename (fallback when media ID is unknown).
  # Only checks the first page (100 items) — sufficient for most catalogs.
  defp search_album_for_item(token, album_id, item) do
    filename = "#{sanitize_filename(item.title)}.jpg"

    response =
      Req.post!(
        "#{@photos_base}/mediaItems:search",
        json: %{albumId: album_id, pageSize: 100},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 ->
        media_items = response.body["mediaItems"] || []

        case Enum.find(media_items, &(&1["filename"] == filename)) do
          nil -> nil
          found -> found["id"]
        end

      _ ->
        nil
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
