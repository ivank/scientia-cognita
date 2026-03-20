defmodule ScientiaCognita.Workers.RenderWorker do
  use Oban.Worker, queue: :process, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => _item_id}}) do
    # TODO: implemented in Task 15
    :ok
  end
end
