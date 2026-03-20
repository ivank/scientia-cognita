defmodule ScientiaCognita.ItemFSM do
  @moduledoc """
  Pure state transition validator for Item image pipeline.
  No side effects — only validates whether a transition is allowed.
  """

  alias ScientiaCognita.Catalog.Item

  @spec transition(Item.t(), atom()) :: {:ok, String.t()} | {:error, :invalid_transition}

  def transition(%Item{status: "pending"}, :start), do: {:ok, "downloading"}
  def transition(%Item{status: "downloading"}, :downloaded), do: {:ok, "processing"}
  def transition(%Item{status: "processing"}, :processed), do: {:ok, "color_analysis"}
  def transition(%Item{status: "color_analysis"}, :colors_ready), do: {:ok, "render"}
  def transition(%Item{status: "render"}, :rendered), do: {:ok, "ready"}
  def transition(%Item{status: status}, :failed) when status not in ["ready", "failed"],
    do: {:ok, "failed"}
  def transition(_, _), do: {:error, :invalid_transition}
end
