defmodule ScientiaCognita.Workers.DeleteAlbumWorker do
  @moduledoc """
  Oban worker that deletes a Google Photos album created by this app.

  Attempts DELETE /v1/albums/:id. If the endpoint returns 404/405
  (not supported by this API version), falls back to removing all
  items from the album via batchRemoveMediaItems, leaving it empty.

  Authorization: verifies export.user_id == user_id before proceeding.

  Status flow: running → deleting → deleted (success) or running (error).
  On error the export is reset to "done" and an {:export_delete_error} event
  is broadcast so the LiveView can offer a "delete local record" escape hatch.
  """

  use Oban.Worker, queue: :export, max_attempts: 2

  require Logger

  alias ScientiaCognita.{Accounts, Photos, Repo}
  alias ScientiaCognita.Photos.{PhotoExport, GoogleErrors}

  @photos_base "https://photoslibrary.googleapis.com/v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_export_id" => export_id, "user_id" => user_id}}) do
    export = Repo.get!(PhotoExport, export_id)
    user = Accounts.get_user!(user_id)

    # Authorization guard — never process another user's export
    if export.user_id != user.id do
      {:error, :unauthorized}
    else
      topic = "export:#{export.catalog_id}:#{user_id}"
      token = user.google_access_token

      # Mark as deleting so the LiveView can show progress
      {:ok, export} = Photos.set_export_status(export, "deleting")

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        topic,
        {:export_deleting, %{}}
      )

      case delete_or_clear_album(token, export.album_id) do
        :ok ->
          {:ok, _} = Photos.set_export_status(export, "deleted")

          Phoenix.PubSub.broadcast(
            ScientiaCognita.PubSub,
            topic,
            {:export_deleted, %{}}
          )

          :ok

        {:error, raw_reason} ->
          friendly = GoogleErrors.translate(to_string(raw_reason))

          # Reset to "done" so the user can retry or keep using the export
          Photos.set_export_status(export, "done")

          Phoenix.PubSub.broadcast(
            ScientiaCognita.PubSub,
            topic,
            {:export_delete_error, friendly}
          )

          {:error, friendly}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Attempt DELETE; fall back to clearing items if DELETE is unsupported.
  defp delete_or_clear_album(token, album_id) do
    response =
      Req.delete!(
        "#{@photos_base}/albums/#{album_id}",
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      s when s in [200, 204] ->
        :ok

      s when s in [404, 405] ->
        # API doesn't support album deletion — clear all items instead
        Logger.warning(
          "Google Photos album DELETE not supported (HTTP #{s}), falling back to clearing items"
        )

        clear_album_items(token, album_id)

      _ ->
        {:error, "HTTP #{response.status}: #{inspect(response.body)}"}
    end
  end

  defp clear_album_items(token, album_id) do
    # NOTE: only fetches first 100 items — known limitation for large albums
    case list_album_media_item_ids(token, album_id) do
      {:ok, []} ->
        :ok

      {:ok, media_item_ids} ->
        media_item_ids
        |> Enum.chunk_every(50)
        |> Enum.reduce_while(:ok, fn chunk, :ok ->
          response =
            Req.post!(
              "#{@photos_base}/albums/#{album_id}:batchRemoveMediaItems",
              json: %{mediaItemIds: chunk},
              headers: [{"Authorization", "Bearer #{token}"}]
            )

          case response.status do
            200 ->
              {:cont, :ok}

            status ->
              {:halt,
               {:error, "batchRemoveMediaItems failed HTTP #{status}: #{inspect(response.body)}"}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_album_media_item_ids(token, album_id) do
    response =
      Req.post!(
        "#{@photos_base}/mediaItems:search",
        json: %{albumId: album_id, pageSize: 100},
        headers: [{"Authorization", "Bearer #{token}"}]
      )

    case response.status do
      200 ->
        ids =
          (response.body["mediaItems"] || [])
          |> Enum.map(& &1["id"])

        {:ok, ids}

      _ ->
        {:error, "Could not list album items: HTTP #{response.status}"}
    end
  end
end
