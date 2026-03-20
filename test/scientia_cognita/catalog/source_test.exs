defmodule ScientiaCognita.Catalog.SourceTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.Source

  describe "html_changeset/2" do
    test "casts raw_html" do
      source = %Source{status: "fetching"}
      cs = Source.html_changeset(source, %{raw_html: "<html>content</html>"})
      assert cs.valid?
      assert get_change(cs, :raw_html) == "<html>content</html>"
    end
  end

  describe "analyze_changeset/2" do
    test "casts gallery_title and gallery_description only" do
      source = %Source{status: "extracting"}

      attrs = %{
        gallery_title: "Hubble Gallery",
        gallery_description: "Space images"
      }

      cs = Source.analyze_changeset(source, attrs)
      assert cs.valid?
      assert get_change(cs, :gallery_title) == "Hubble Gallery"
      assert get_change(cs, :gallery_description) == "Space images"
    end

    test "does not cast selector fields (they no longer exist)" do
      source = %Source{status: "extracting"}
      cs = Source.analyze_changeset(source, %{gallery_title: "Test", selector_image: ".foo"})
      assert cs.valid?
      # selector_image is not a schema field; cast silently ignores unknown keys
      assert get_change(cs, :gallery_title) == "Test"
    end
  end

  describe "status_changeset/3" do
    test "accepts FSM statuses" do
      for status <- ~w(pending fetching extracting done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects analyzing (removed from FSM)" do
      cs = Source.status_changeset(%Source{status: "pending"}, "analyzing")
      refute cs.valid?
    end

    test "rejects old running status" do
      cs = Source.status_changeset(%Source{status: "pending"}, "running")
      refute cs.valid?
    end
  end
end
