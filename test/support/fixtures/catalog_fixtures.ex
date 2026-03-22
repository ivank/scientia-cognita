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
        {:ok, source} =
          source
          |> Ecto.Changeset.change(raw_html: raw_html)
          |> ScientiaCognita.Repo.update()

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
    {status, attrs}          = Map.pop(attrs, :status, "pending")
    {original_image, attrs}  = Map.pop(attrs, :original_image)
    {processed_image, attrs} = Map.pop(attrs, :processed_image)
    {final_image, attrs}     = Map.pop(attrs, :final_image)
    {text_color, attrs}      = Map.pop(attrs, :text_color)
    {bg_color, attrs}        = Map.pop(attrs, :bg_color)
    {bg_opacity, attrs}      = Map.pop(attrs, :bg_opacity)

    {:ok, item} =
      attrs
      |> Enum.into(%{
        title: "Test Image",
        original_url: "https://example.com/image-#{System.unique_integer([:positive])}.jpg",
        source_id: source.id
      })
      |> Catalog.create_item()

    # Use Ecto.Changeset.change/2 (not cast) to set image fields with plain
    # string filenames — bypasses Waffle.Ecto.Type.cast/1, which is correct for
    # test setup where we're simulating an already-stored file, not uploading one.
    # Waffle.Ecto.Type.dump/2 requires a map, so plain strings are wrapped.
    wrap_image = fn
      nil -> nil
      s when is_binary(s) -> %{file_name: s, updated_at: nil}
      m -> m
    end

    item =
      if original_image || processed_image || final_image do
        changes =
          %{}
          |> then(fn a -> if original_image,  do: Map.put(a, :original_image,  wrap_image.(original_image)),  else: a end)
          |> then(fn a -> if processed_image, do: Map.put(a, :processed_image, wrap_image.(processed_image)), else: a end)
          |> then(fn a -> if final_image,     do: Map.put(a, :final_image,     wrap_image.(final_image)),     else: a end)

        {:ok, item} =
          item
          |> Ecto.Changeset.change(changes)
          |> ScientiaCognita.Repo.update()

        item
      else
        item
      end

    item =
      if text_color && bg_color && bg_opacity do
        {:ok, item} =
          ScientiaCognita.Catalog.update_item_colors(item, %{
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
