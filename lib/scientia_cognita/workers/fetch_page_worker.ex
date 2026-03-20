defmodule ScientiaCognita.Workers.FetchPageWorker do
  @moduledoc """
  Fetches the source URL, saves raw HTML to the source record,
  and enqueues AnalyzePageWorker.

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, SourceFSM}
  alias ScientiaCognita.Workers.AnalyzePageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[FetchPageWorker] source=#{source_id} url=#{source.url}")

    with {:ok, "fetching"} <- SourceFSM.transition(source, :start),
         {:ok, source} <- Catalog.update_source_status(source, "fetching"),
         {:ok, html} <- fetch(source.url),
         {:ok, source} <- Catalog.update_source_html(source, %{raw_html: html}),
         {:ok, "analyzing"} <- SourceFSM.transition(source, :fetched),
         {:ok, source} <- Catalog.update_source_status(source, "analyzing") do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id} |> AnalyzePageWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[FetchPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[FetchPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok
    end
  end

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
