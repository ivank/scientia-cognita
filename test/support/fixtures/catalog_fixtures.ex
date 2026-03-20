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

  @doc "Creates a source in `extracting` status — ready for ExtractPageWorker."
  def extracting_source_fixture(attrs \\ %{}) do
    source = source_fixture(attrs)
    {:ok, source} = Catalog.update_source_status(source, "extracting")
    source
  end

  def item_fixture(source, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status, "pending")
    {storage_key, attrs} = Map.pop(attrs, :storage_key)
    {processed_key, attrs} = Map.pop(attrs, :processed_key)
    {text_color, attrs} = Map.pop(attrs, :text_color)
    {bg_color, attrs} = Map.pop(attrs, :bg_color)
    {bg_opacity, attrs} = Map.pop(attrs, :bg_opacity)

    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image-#{System.unique_integer([:positive])}.jpg",
        source_id: source.id
      })
      |> Catalog.create_item()

    item =
      if storage_key || processed_key do
        storage_attrs =
          %{}
          |> then(fn a -> if storage_key, do: Map.put(a, :storage_key, storage_key), else: a end)
          |> then(fn a -> if processed_key, do: Map.put(a, :processed_key, processed_key), else: a end)
        {:ok, item} = ScientiaCognita.Catalog.update_item_storage(item, storage_attrs)
        item
      else
        item
      end

    item =
      if text_color && bg_color && bg_opacity do
        {:ok, item} = ScientiaCognita.Catalog.update_item_colors(item, %{
          text_color: text_color,
          bg_color: bg_color,
          bg_opacity: bg_opacity
        })
        item
      else
        item
      end

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
