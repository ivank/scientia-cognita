defmodule ScientiaCognita.Catalog.SourceTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Catalog.{Source, GeminiPageResult}

  describe "status_changeset/3" do
    test "accepts all FSM statuses including items_loading" do
      for status <- ~w(pending fetching extracting items_loading done failed) do
        cs = Source.status_changeset(%Source{status: "pending"}, status)
        assert cs.valid?, "Expected #{status} to be valid"
      end
    end

    test "rejects unknown status" do
      cs = Source.status_changeset(%Source{status: "pending"}, "analyzing")
      refute cs.valid?
    end
  end

  describe "transition_changeset/4 — fetching → extracting" do
    test "requires raw_html" do
      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "fetching"}),
          "fetching",
          "extracting",
          %{}
        )

      refute cs.valid?
      assert {:raw_html, {"can't be blank", _}} = hd(cs.errors)
    end

    test "accepts raw_html" do
      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "fetching"}),
          "fetching",
          "extracting",
          %{raw_html: "<html>ok</html>"}
        )

      assert cs.valid?
    end
  end

  describe "transition_changeset/4 — failed" do
    test "requires error message" do
      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "extracting"}),
          "extracting",
          "failed",
          %{}
        )

      refute cs.valid?
    end

    test "accepts error message" do
      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "extracting"}),
          "extracting",
          "failed",
          %{error: "Something went wrong"}
        )

      assert cs.valid?
    end
  end

  describe "transition_changeset/4 — extracting → items_loading" do
    test "appends gemini_page to gemini_pages" do
      page =
        GeminiPageResult.new(%{
          page_url: "https://example.com",
          is_gallery: true,
          gallery_title: "Test",
          gallery_description: "Desc",
          next_page_url: nil,
          raw_items: []
        })

      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "extracting", gemini_pages: []}),
          "extracting",
          "items_loading",
          %{
            pages_fetched: 1,
            total_items: 0,
            title: "Test",
            description: "Desc",
            gemini_page: page
          }
        )

      assert cs.valid?
      assert length(Ecto.Changeset.get_change(cs, :gemini_pages)) == 1
    end

    test "stores gallery copyright when provided" do
      page =
        GeminiPageResult.new(%{
          page_url: "https://example.com",
          is_gallery: true,
          gallery_title: "Test",
          gallery_description: nil,
          gallery_copyright: "© ESA/Hubble",
          next_page_url: nil,
          raw_items: []
        })

      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "extracting", gemini_pages: []}),
          "extracting",
          "items_loading",
          %{
            pages_fetched: 1,
            total_items: 0,
            title: "Test",
            description: nil,
            copyright: "© ESA/Hubble",
            gemini_page: page
          }
        )

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :copyright) == "© ESA/Hubble"
    end

    test "copyright is nil when not provided" do
      page =
        GeminiPageResult.new(%{
          page_url: "https://example.com",
          is_gallery: true,
          gallery_title: "Test",
          gallery_description: nil,
          next_page_url: nil,
          raw_items: []
        })

      cs =
        Source.transition_changeset(
          Ecto.Changeset.change(%Source{status: "extracting", gemini_pages: []}),
          "extracting",
          "items_loading",
          %{
            pages_fetched: 1,
            total_items: 0,
            title: "Test",
            description: nil,
            gemini_page: page
          }
        )

      assert cs.valid?
      assert is_nil(Ecto.Changeset.get_change(cs, :copyright))
    end
  end
end
