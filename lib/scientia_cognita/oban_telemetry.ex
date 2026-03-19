defmodule ScientiaCognita.ObanTelemetry do
  @moduledoc """
  Listens for Oban job discard events and marks the associated item as "failed"
  so the UI reflects the true state instead of leaving items stuck in
  "downloading" or "processing".
  """

  require Logger

  @item_workers [
    "ScientiaCognita.Workers.DownloadImageWorker",
    "ScientiaCognita.Workers.ProcessImageWorker"
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
    maybe_mark_item_failed(job)
  end

  def handle_job_stop(_event, _measurements, _meta, _config), do: :ok

  defp maybe_mark_item_failed(%Oban.Job{worker: worker, args: %{"item_id" => item_id}, errors: errors})
       when worker in @item_workers do
    last_error =
      case List.last(errors) do
        %{"error" => msg} -> truncate(msg, 500)
        _ -> "Job discarded after maximum attempts"
      end

    try do
      item = ScientiaCognita.Catalog.get_item!(item_id)
      {:ok, item} = ScientiaCognita.Catalog.update_item_status(item, "failed", error: last_error)

      Phoenix.PubSub.broadcast(
        ScientiaCognita.PubSub,
        "source:#{item.source_id}",
        {:item_updated, item}
      )
    rescue
      e -> Logger.error("[ObanTelemetry] Failed to mark item #{item_id} as failed: #{inspect(e)}")
    end
  end

  defp maybe_mark_item_failed(_job), do: :ok

  defp truncate(str, max) when byte_size(str) > max, do: binary_part(str, 0, max) <> "…"
  defp truncate(str, _max), do: str
end
