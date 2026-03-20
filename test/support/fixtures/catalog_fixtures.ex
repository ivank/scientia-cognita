defmodule ScientiaCognita.CatalogFixtures do
  alias ScientiaCognita.Catalog

  def source_fixture(attrs \\ %{}) do
    {:ok, source} =
      attrs
      |> Enum.into(%{
        name: "Test Gallery",
        url: unique_url(),
        status: "pending"
      })
      |> Catalog.create_source()

    source
  end

  def analyzed_source_fixture(attrs \\ %{}) do
    source = source_fixture(Map.merge(%{status: "extracting"}, Map.drop(attrs, [:selector_title, :selector_image, :selector_description, :selector_copyright, :selector_next_page, :gallery_title, :gallery_description])))

    analysis_attrs = attrs
      |> Map.take([:selector_title, :selector_image, :selector_description, :selector_copyright, :selector_next_page, :gallery_title, :gallery_description])
      |> Enum.into(%{
        gallery_title: "Test Gallery",
        gallery_description: "A test gallery",
        selector_title: ".item-title",
        selector_image: ".item img",
        selector_description: ".item-desc",
        selector_copyright: ".item-copy",
        selector_next_page: "a.next-page"
      })

    {:ok, source} = Catalog.update_source_analysis(source, analysis_attrs)
    source
  end

  def item_fixture(source, attrs \\ %{}) do
    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image-#{System.unique_integer([:positive])}.jpg",
        source_id: source.id,
        status: "pending"
      })
      |> Catalog.create_item()

    item
  end

  defp unique_url do
    "https://example-#{System.unique_integer([:positive])}.com/gallery"
  end
end
