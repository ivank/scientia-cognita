defmodule ScientiaCognita.SourceFSMTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.SourceFSM
  alias ScientiaCognita.Catalog.Source

  defp source(status), do: %Source{status: status}

  describe "valid transitions" do
    test "pending + :start → fetching" do
      assert {:ok, "fetching"} = SourceFSM.transition(source("pending"), :start)
    end

    test "fetching + :fetched → analyzing" do
      assert {:ok, "analyzing"} = SourceFSM.transition(source("fetching"), :fetched)
    end

    test "analyzing + :analyzed → extracting" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("analyzing"), :analyzed)
    end

    test "analyzing + :not_gallery → failed" do
      assert {:ok, "failed"} = SourceFSM.transition(source("analyzing"), :not_gallery)
    end

    test "extracting + :page_done → extracting (self-loop)" do
      assert {:ok, "extracting"} = SourceFSM.transition(source("extracting"), :page_done)
    end

    test "extracting + :exhausted → done" do
      assert {:ok, "done"} = SourceFSM.transition(source("extracting"), :exhausted)
    end

    test ":failed from any non-terminal state" do
      for status <- ~w(pending fetching analyzing extracting) do
        assert {:ok, "failed"} = SourceFSM.transition(source(status), :failed),
               "Expected :failed to work from #{status}"
      end
    end
  end

  describe "invalid transitions" do
    test "wrong event for state" do
      assert {:error, :invalid_transition} = SourceFSM.transition(source("pending"), :fetched)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("fetching"), :start)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("done"), :start)
      assert {:error, :invalid_transition} = SourceFSM.transition(source("failed"), :start)
    end
  end
end
