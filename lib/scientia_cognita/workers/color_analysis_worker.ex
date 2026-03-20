defmodule ScientiaCognita.Workers.ColorAnalysisWorker do
  use Oban.Worker, queue: :process, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => _item_id}}) do
    # TODO: implemented in Task 14
    :ok
  end
end
