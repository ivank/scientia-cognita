defmodule ScientiaCognita.Catalog do
  @moduledoc """
  Context for Sources, Items, Catalogs, and their relationships.
  """

  import Ecto.Query
  alias ScientiaCognita.Repo
  alias ScientiaCognita.Catalog.{Source, Item, Catalog, CatalogItem}

  # ---------------------------------------------------------------------------
  # Sources
  # ---------------------------------------------------------------------------

  def list_sources do
    Repo.all(from s in Source, order_by: [desc: s.inserted_at])
  end

  def get_source!(id), do: Repo.get!(Source, id)

  def create_source(attrs) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  def update_source_status(%Source{} = source, status, opts \\ []) do
    source
    |> Source.status_changeset(status, opts)
    |> Repo.update()
  end

  def update_source_progress(%Source{} = source, attrs) do
    source
    |> Source.progress_changeset(attrs)
    |> Repo.update()
  end

  def delete_source(%Source{} = source), do: Repo.delete(source)

  def change_source(%Source{} = source, attrs \\ %{}), do: Source.changeset(source, attrs)

  # ---------------------------------------------------------------------------
  # Items
  # ---------------------------------------------------------------------------

  def list_items_by_source(%Source{id: source_id}) do
    Repo.all(from i in Item, where: i.source_id == ^source_id, order_by: [asc: i.inserted_at])
  end

  def list_items_by_source(source_id) when is_integer(source_id) do
    Repo.all(from i in Item, where: i.source_id == ^source_id, order_by: [asc: i.inserted_at])
  end

  def get_item!(id), do: Repo.get!(Item, id)

  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def update_item_status(%Item{} = item, status, opts \\ []) do
    item
    |> Item.status_changeset(status, opts)
    |> Repo.update()
  end

  def update_item_storage(%Item{} = item, attrs) do
    item
    |> Item.storage_changeset(attrs)
    |> Repo.update()
  end

  def count_items_by_status(%Source{id: source_id}) do
    Repo.all(
      from i in Item,
        where: i.source_id == ^source_id,
        group_by: i.status,
        select: {i.status, count(i.id)}
    )
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Catalogs
  # ---------------------------------------------------------------------------

  def list_catalogs do
    Repo.all(from c in Catalog, order_by: [asc: c.name])
  end

  def get_catalog!(id), do: Repo.get!(Catalog, id)

  def get_catalog_by_slug!(slug) do
    Repo.get_by!(Catalog, slug: slug)
  end

  def create_catalog(attrs) do
    %Catalog{}
    |> Catalog.changeset(attrs)
    |> Repo.insert()
  end

  def update_catalog(%Catalog{} = catalog, attrs) do
    catalog
    |> Catalog.changeset(attrs)
    |> Repo.update()
  end

  def delete_catalog(%Catalog{} = catalog), do: Repo.delete(catalog)

  def change_catalog(%Catalog{} = catalog, attrs \\ %{}), do: Catalog.changeset(catalog, attrs)

  # ---------------------------------------------------------------------------
  # CatalogItems
  # ---------------------------------------------------------------------------

  def list_catalog_items(%Catalog{id: catalog_id}) do
    Repo.all(
      from i in Item,
        join: ci in CatalogItem,
        on: ci.item_id == i.id,
        where: ci.catalog_id == ^catalog_id,
        order_by: [asc: ci.position, asc: ci.inserted_at],
        preload: [:source]
    )
  end

  def add_items_to_catalog(%Catalog{id: catalog_id}, item_ids) when is_list(item_ids) do
    now = DateTime.utc_now(:second)

    entries =
      Enum.map(item_ids, fn item_id ->
        %{catalog_id: catalog_id, item_id: item_id, position: 0,
          inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(CatalogItem, entries,
      on_conflict: :nothing,
      conflict_target: [:catalog_id, :item_id]
    )
  end

  def remove_item_from_catalog(%Catalog{id: catalog_id}, item_id) do
    Repo.delete_all(
      from ci in CatalogItem,
        where: ci.catalog_id == ^catalog_id and ci.item_id == ^item_id
    )
  end

  def item_in_catalog?(%Catalog{id: catalog_id}, item_id) do
    Repo.exists?(
      from ci in CatalogItem,
        where: ci.catalog_id == ^catalog_id and ci.item_id == ^item_id
    )
  end
end
