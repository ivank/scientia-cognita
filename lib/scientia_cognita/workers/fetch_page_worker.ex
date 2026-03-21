defmodule ScientiaCognita.Workers.FetchPageWorker do
  @moduledoc """
  Fetches the source URL, saves raw HTML atomically via fsmx transition,
  and enqueues ExtractPageWorker.

  State transitions: pending → fetching → extracting

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, Repo}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[FetchPageWorker] source=#{source_id} url=#{source.url}")

    with {:ok, source} <- fsm_transition(source, "fetching"),
         {:ok, html} <- fetch(source.url),
         {:ok, source} <- fsm_transition(source, "extracting", %{raw_html: html}) do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id, url: source.url} |> ExtractPageWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[FetchPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[FetchPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = fsm_transition(source, "failed", %{error: inspect(reason)})
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

  defp fsm_transition(schema, new_state, params \\ %{}) do
    Ecto.Multi.new()
    |> Fsmx.transition_multi(schema, :transition, new_state, params, state_field: :status)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: updated}} -> {:ok, updated}
      {:error, :transition, %Ecto.Changeset{} = cs, _} ->
        if Keyword.has_key?(cs.errors, :status) do
          {:error, :invalid_transition}
        else
          {:error, cs}
        end
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
