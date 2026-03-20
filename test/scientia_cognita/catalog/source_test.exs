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
    test "casts all selector fields and gallery metadata" do
      source = %Source{status: "analyzing"}

      attrs = %{
        gallery_title: "Hubble Gallery",
        gallery_description: "Space images",
        selector_title: ".caption h3",
        selector_image: ".gallery-item img",
        selector_description: ".caption p",
        selector_copyright: ".credit",
        selector_next_page: "a.next"
      }

      cs = Source.analyze_changeset(source, attrs)
      assert cs.valid?
      assert get_change(cs, :gallery_title) == "Hubble Gallery"
      assert get_change(cs, :selector_image) == ".gallery-item img"
    end
  end

  describe "status_changeset/3" do
    test "accepts new FSM statuses" do
      for status <- ~w(pending fetching analyzing extracting done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects old running status" do
      cs = Source.status_changeset(%Source{status: "pending"}, "running")
      refute cs.valid?
    end
  end
end
