defmodule ScientiaCognita.Workers.DownloadImageWorker do
  @moduledoc """
  Downloads an item's original image from its source URL and uploads it to MinIO.
  On success, enqueues ProcessImageWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, Storage}
  alias ScientiaCognita.Workers.ProcessImageWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)

    unless item.original_url do
      Logger.warning("[DownloadImageWorker] item=#{item_id} has no original_url, skipping")
      return(:ok)
    end

    Logger.info("[DownloadImageWorker] item=#{item_id} url=#{item.original_url}")

    {:ok, _} = Catalog.update_item_status(item, "downloading")

    with {:ok, {binary, content_type}} <- download_image(item.original_url),
         ext = ext_from_content_type(content_type),
         storage_key = Storage.item_key(item.id, :original, ext),
         {:ok, _} <- Storage.upload(storage_key, binary, content_type: content_type),
         {:ok, item} <- Catalog.update_item_storage(item, %{storage_key: storage_key}),
         {:ok, _} <- Catalog.update_item_status(item, "processing") do
      broadcast(item.source_id, {:item_updated, item})

      %{item_id: item_id}
      |> ProcessImageWorker.new()
      |> Oban.insert()

      :ok
    else
      {:error, reason} ->
        Logger.error("[DownloadImageWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, item})
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------

  defp download_image(url) do
    case Req.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          case Map.get(headers, "content-type") do
            [ct | _] -> ct |> String.split(";") |> hd() |> String.trim()
            nil -> "image/jpeg"
          end

        {:ok, {body, content_type}}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ext_from_content_type("image/jpeg"), do: ".jpg"
  defp ext_from_content_type("image/png"), do: ".png"
  defp ext_from_content_type("image/webp"), do: ".webp"
  defp ext_from_content_type("image/gif"), do: ".gif"
  defp ext_from_content_type(_), do: ".jpg"

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end

  defp return(value), do: value
end
