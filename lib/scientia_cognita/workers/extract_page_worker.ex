defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  Extracts gallery items from a source page using the CSS selectors determined
  by AnalyzePageWorker.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker, queue: :fetch, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => _source_id, "url" => _url}}) do
    # TODO: implement in Task 11
    :ok
  end
end
