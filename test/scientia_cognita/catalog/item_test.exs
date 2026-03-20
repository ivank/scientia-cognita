defmodule ScientiaCognita.Catalog.ItemTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.Item

  describe "color_changeset/2" do
    test "casts color fields" do
      item = %Item{status: "color_analysis"}

      cs = Item.color_changeset(item, %{
        text_color: "#FFFFFF",
        bg_color: "#1A1A2E",
        bg_opacity: 0.75
      })

      assert cs.valid?
      assert get_change(cs, :text_color) == "#FFFFFF"
      assert get_change(cs, :bg_color) == "#1A1A2E"
      assert get_change(cs, :bg_opacity) == 0.75
    end
  end

  describe "status_changeset/3" do
    test "accepts new FSM statuses" do
      for status <- ~w(pending downloading processing color_analysis render ready failed) do
        cs = Item.status_changeset(%Item{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end
  end
end
