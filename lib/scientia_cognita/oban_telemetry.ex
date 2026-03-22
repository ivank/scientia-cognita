defmodule ScientiaCognita.ObanTelemetry do
  @moduledoc """
  Listens for Oban job discard events and transitions the associated item to
  "discarded" so the UI reflects the true state and the item can be bulk-retried.
  """

  require Logger

  alias ScientiaCognita.{Catalog, Repo}

  @item_workers [
    "ScientiaCognita.Workers.DownloadImageWorker",
    "ScientiaCognita.Workers.ThumbnailWorker",
    "ScientiaCognita.Workers.AnalyzeWorker",
    "ScientiaCognita.Workers.ResizeWorker",
    "ScientiaCognita.Workers.RenderWorker"
  ]

  def attach do
    :telemetry.attach(
      "scientia-oban-job-discard",
      [:oban, :job, :stop],
      &__MODULE__.handle_job_stop/4,
      nil
    )
  end

  def handle_job_stop(_event, _measurements, %{state: :discard, job: job}, _config) do
    maybe_mark_item_discarded(job)
  end

  def handle_job_stop(_event, _measurements, _meta, _config), do: :ok

  defp maybe_mark_item_discarded(%Oban.Job{
         worker: worker,
         args: %{"item_id" => item_id},
         errors: errors
       })
       when worker in @item_workers do
    last_error =
      case List.last(errors) do
        %{"error" => msg} -> truncate(msg, 500)
        _ -> "Job discarded after maximum attempts"
      end

    try do
      item = Catalog.get_item!(item_id)

      result =
        Ecto.Multi.new()
        |> Fsmx.transition_multi(item, :transition, "discarded", %{error: last_error},
          state_field: :status
        )
        |> Repo.transaction()

      case result do
        {:ok, %{transition: updated}} ->
          Phoenix.PubSub.broadcast(
            ScientiaCognita.PubSub,
            "source:#{updated.source_id}",
            {:item_updated, updated}
          )

        {:error, :transition, _cs, _} ->
          # Item is already in a terminal state (ready/failed/discarded) — nothing to do.
          :ok

        {:error, _, reason, _} ->
          Logger.error(
            "[ObanTelemetry] Failed to discard item=#{item_id}: #{inspect(reason)}"
          )
      end
    rescue
      e ->
        Logger.error("[ObanTelemetry] Error discarding item=#{item_id}: #{inspect(e)}")
    end
  end

  defp maybe_mark_item_discarded(_job), do: :ok

  defp truncate(str, max) when byte_size(str) > max, do: binary_part(str, 0, max) <> "…"
  defp truncate(str, _max), do: str
end
