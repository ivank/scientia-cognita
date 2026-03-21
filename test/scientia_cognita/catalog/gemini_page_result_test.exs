defmodule ScientiaCognita.Catalog.GeminiPageResultTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.Catalog.GeminiPageResult

  describe "new/1" do
    test "derives items_count from length of raw_items" do
      result = GeminiPageResult.new(%{
        page_url: "https://example.com/gallery",
        is_gallery: true,
        gallery_title: "Test Gallery",
        gallery_description: "A test gallery",
        next_page_url: nil,
        raw_items: [%{"image_url" => "https://example.com/1.jpg"}]
      })

      assert result.items_count == 1
      assert result.page_url == "https://example.com/gallery"
      assert result.is_gallery == true
      assert result.gallery_title == "Test Gallery"
      assert result.raw_items == [%{"image_url" => "https://example.com/1.jpg"}]
    end

    test "items_count is 0 for empty raw_items" do
      result = GeminiPageResult.new(%{
        page_url: "https://example.com",
        is_gallery: false,
        gallery_title: nil,
        gallery_description: nil,
        next_page_url: nil,
        raw_items: []
      })

      assert result.items_count == 0
    end

    test "sets generated_at to current UTC second" do
      before = DateTime.utc_now(:second)
      result = GeminiPageResult.new(%{page_url: "x", is_gallery: false,
        gallery_title: nil, gallery_description: nil, next_page_url: nil, raw_items: []})
      after_t = DateTime.utc_now(:second)

      assert DateTime.compare(result.generated_at, before) in [:gt, :eq]
      assert DateTime.compare(result.generated_at, after_t) in [:lt, :eq]
    end
  end

  describe "changeset/2" do
    test "casts all fields successfully" do
      attrs = %{
        page_url: "https://example.com",
        is_gallery: true,
        gallery_title: "Test",
        gallery_description: "Desc",
        next_page_url: nil,
        items_count: 5,
        raw_items: [%{"image_url" => "https://example.com/1.jpg"}],
        generated_at: DateTime.utc_now(:second)
      }

      cs = GeminiPageResult.changeset(%GeminiPageResult{}, attrs)
      assert cs.valid?
    end
  end
end
