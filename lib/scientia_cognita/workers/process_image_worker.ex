defmodule ScientiaCognita.Workers.ProcessImageWorker do
  @moduledoc """
  Downloads an item's original image from MinIO, resizes and crops it to
  1920×1080 (16:9 FHD), and uploads the processed variant.
  On success, enqueues ColorAnalysisWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, ItemFSM, Storage}
  alias ScientiaCognita.Workers.ColorAnalysisWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @target_width 1920
  @target_height 1080

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[ProcessImageWorker] item=#{item_id}")

    with {:ok, original_binary} <- download_original(item.storage_key),
         {:ok, img} <- Image.from_binary(original_binary),
         {:ok, resized} <- Image.thumbnail(img, @target_width,
           height: @target_height, crop: :center),
         {:ok, output_binary} <- Image.write(resized, :memory, suffix: ".jpg", quality: 85),
         processed_key = Storage.item_key(item.id, :processed, ".jpg"),
         {:ok, _} <- @storage.upload(processed_key, output_binary, content_type: "image/jpeg"),
         {:ok, item} <- Catalog.update_item_storage(item, %{processed_key: processed_key}),
         {:ok, "color_analysis"} <- ItemFSM.transition(item, :processed),
         {:ok, item} <- Catalog.update_item_status(item, "color_analysis") do
      broadcast(item.source_id, {:item_updated, item})
      %{item_id: item_id} |> ColorAnalysisWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[ProcessImageWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ProcessImageWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  end

  defp download_original(nil), do: {:error, "item has no storage_key"}

  defp download_original(storage_key) do
    url = Storage.get_url(storage_key)

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
