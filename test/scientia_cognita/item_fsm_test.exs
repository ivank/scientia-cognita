defmodule ScientiaCognita.ItemFSMTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.ItemFSM
  alias ScientiaCognita.Catalog.Item

  defp item(status), do: %Item{status: status}

  describe "valid transitions" do
    test "pending + :start → downloading" do
      assert {:ok, "downloading"} = ItemFSM.transition(item("pending"), :start)
    end

    test "downloading + :downloaded → processing" do
      assert {:ok, "processing"} = ItemFSM.transition(item("downloading"), :downloaded)
    end

    test "processing + :processed → color_analysis" do
      assert {:ok, "color_analysis"} = ItemFSM.transition(item("processing"), :processed)
    end

    test "color_analysis + :colors_ready → render" do
      assert {:ok, "render"} = ItemFSM.transition(item("color_analysis"), :colors_ready)
    end

    test "render + :rendered → ready" do
      assert {:ok, "ready"} = ItemFSM.transition(item("render"), :rendered)
    end

    test ":failed from any non-terminal state" do
      for status <- ~w(pending downloading processing color_analysis render) do
        assert {:ok, "failed"} = ItemFSM.transition(item(status), :failed),
               "Expected :failed to work from #{status}"
      end
    end
  end

  describe "invalid transitions" do
    test "wrong event for state" do
      assert {:error, :invalid_transition} = ItemFSM.transition(item("pending"), :downloaded)
      assert {:error, :invalid_transition} = ItemFSM.transition(item("ready"), :start)
      assert {:error, :invalid_transition} = ItemFSM.transition(item("failed"), :start)
    end
  end
end
