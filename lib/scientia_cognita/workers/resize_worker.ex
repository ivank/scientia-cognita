defmodule ScientiaCognita.Workers.ResizeWorker do
  @moduledoc """
  Downloads the original image from S3, resizes and crops it to 1920×1080
  using attention-based cropping to focus on the subject identified during
  analysis. Uploads the result and enqueues RenderWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 5

  require Logger

  alias ScientiaCognita.{Catalog, Repo}
  alias ScientiaCognita.Workers.RenderWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @uploader Application.compile_env(
              :scientia_cognita,
              :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader
            )

  @target_width 1920
  @target_height 1080

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[ResizeWorker] item=#{item_id}")

    with {:ok, original_binary} <- download_original(item),
         {:ok, img} <- Image.from_binary(original_binary),
         {:ok, resized} <-
           Image.thumbnail(img, @target_width, height: @target_height, crop: :attention),
         {:ok, output_binary} <- Image.write(resized, :memory, suffix: ".jpg", quality: 85),
         {:ok, file} <-
           @uploader.store({%{filename: "processed.jpg", binary: output_binary}, item}),
         {:ok, item} <-
           fsm_transition(item, "render", %{
             processed_image: %{file_name: file, updated_at: nil}
           }) do
      broadcast(item.source_id, {:item_updated, item})
      %{item_id: item_id} |> RenderWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[ResizeWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ResizeWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  rescue
    e ->
      Logger.error("[ResizeWorker] exception item=#{item_id}: #{inspect(e)}")

      try do
        fresh = Catalog.get_item!(item_id)
        {:ok, failed} = fsm_transition(fresh, "failed", %{error: inspect(e)})
        broadcast(failed.source_id, {:item_updated, failed})
      rescue
        _ -> :ok
      end

      :ok
  end

  defp download_original(%{original_image: nil}), do: {:error, "item has no original_image"}

  defp download_original(item) do
    url = @uploader.url({item.original_image, item})
    Logger.debug("[ResizeWorker] fetching original url=#{url}")

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fsm_transition(schema, new_state, params) do
    Ecto.Multi.new()
    |> Fsmx.transition_multi(schema, :transition, new_state, params, state_field: :status)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: updated}} ->
        {:ok, updated}

      {:error, :transition, %Ecto.Changeset{} = cs, _} ->
        if Keyword.has_key?(cs.errors, :status) do
          {:error, :invalid_transition}
        else
          {:error, cs}
        end

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
