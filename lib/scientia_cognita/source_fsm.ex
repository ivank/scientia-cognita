defmodule ScientiaCognita.SourceFSM do
  @moduledoc """
  Pure state transition validator for Source crawl lifecycle.
  No side effects — only validates whether a transition is allowed.
  """

  alias ScientiaCognita.Catalog.Source

  @spec transition(Source.t(), atom()) :: {:ok, String.t()} | {:error, :invalid_transition}

  def transition(%Source{status: "pending"}, :start), do: {:ok, "fetching"}
  def transition(%Source{status: "fetching"}, :fetched), do: {:ok, "analyzing"}
  def transition(%Source{status: "analyzing"}, :analyzed), do: {:ok, "extracting"}
  def transition(%Source{status: "analyzing"}, :not_gallery), do: {:ok, "failed"}
  def transition(%Source{status: "extracting"}, :page_done), do: {:ok, "extracting"}
  def transition(%Source{status: "extracting"}, :exhausted), do: {:ok, "done"}
  def transition(%Source{status: status}, :failed) when status not in ["done", "failed"],
    do: {:ok, "failed"}
  def transition(_, _), do: {:error, :invalid_transition}
end
