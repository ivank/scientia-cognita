defmodule ScientiaCognita.CatalogFixtures do
  alias ScientiaCognita.Catalog

  def source_fixture(attrs \\ %{}) do
    {raw_html, attrs} = Map.pop(attrs, :raw_html)
    {status, attrs} = Map.pop(attrs, :status, "pending")

    {:ok, source} =
      attrs
      |> Enum.into(%{
        name: "Test Gallery",
        url: unique_url(),
        status: "pending"
      })
      |> Catalog.create_source()

    source =
      if raw_html do
        {:ok, source} = Catalog.update_source_html(source, %{raw_html: raw_html})
        source
      else
        source
      end

    if status != "pending" do
      {:ok, source} = Catalog.update_source_status(source, status)
      source
    else
      source
    end
  end

  def analyzed_source_fixture(attrs \\ %{}) do
    source = source_fixture(attrs)
    {:ok, source} =
      ScientiaCognita.Catalog.update_source_analysis(source, %{
        gallery_title: "Test Gallery",
        gallery_description: "A test gallery",
        selector_title: ".item-title",
        selector_image: ".item-image img",
        selector_description: ".item-desc",
        selector_copyright: ".item-copy",
        selector_next_page: "a.next"
      })
    source
  end

  def item_fixture(source, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status, "pending")

    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image-#{System.unique_integer([:positive])}.jpg",
        source_id: source.id
      })
      |> Catalog.create_item()

    if status != "pending" do
      {:ok, item} = ScientiaCognita.Catalog.update_item_status(item, status)
      item
    else
      item
    end
  end

  defp unique_url do
    "https://example-#{System.unique_integer([:positive])}.com/gallery"
  end
end
