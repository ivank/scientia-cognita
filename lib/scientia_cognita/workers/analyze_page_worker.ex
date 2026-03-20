defmodule ScientiaCognita.Workers.AnalyzePageWorker do
  @moduledoc """
  Analyzes the raw HTML of a source to determine if it is a scientific image gallery,
  then enqueues ExtractPageWorker on success.

  Args: %{source_id: integer}
  """

  use Oban.Worker,
    queue: :analyze,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => _source_id}}) do
    # TODO: implement in Task 10
    :ok
  end
end
