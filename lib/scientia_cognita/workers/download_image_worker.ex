defmodule ScientiaCognita.Workers.DownloadImageWorker do
  @moduledoc """
  Downloads an item's original image from its source URL and uploads it to MinIO.
  On success, enqueues ProcessImageWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :fetch, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, Repo, Storage}
  alias ScientiaCognita.Workers.ProcessImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)

    unless item.original_url do
      Logger.warning("[DownloadImageWorker] item=#{item_id} has no original_url, skipping")
      :ok
    else
      Logger.info("[DownloadImageWorker] item=#{item_id} url=#{item.original_url}")

      with {:ok, item} <- fsm_transition(item, "downloading"),
           {:ok, {binary, content_type}} <- download(item.original_url),
           ext = ext_from_content_type(content_type),
           storage_key = Storage.item_key(item.id, :original, ext),
           {:ok, _} <- @storage.upload(storage_key, binary, content_type: content_type),
           {:ok, item} <- fsm_transition(item, "processing", %{storage_key: storage_key}) do
        broadcast(item.source_id, {:item_updated, item})
        %{item_id: item_id} |> ProcessImageWorker.new() |> Oban.insert()
        :ok
      else
        {:error, :invalid_transition} ->
          Logger.warning("[DownloadImageWorker] invalid transition for item=#{item_id}")
          :ok

        {:error, reason} ->
          Logger.error("[DownloadImageWorker] failed item=#{item_id}: #{inspect(reason)}")
          item = Catalog.get_item!(item_id)
          {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
          broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
          :ok
      end
    end
  end

  defp download(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
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

  defp fsm_transition(schema, new_state, params \\ %{}) do
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
end
