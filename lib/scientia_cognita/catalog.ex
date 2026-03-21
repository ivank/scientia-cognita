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

  def list_sources_with_ready_items do
    Repo.all(
      from s in Source,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM items i WHERE i.source_id = ? AND i.status = 'ready')",
            s.id
          ),
        order_by: [asc: s.name]
    )
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

  def delete_source(%Source{} = source), do: Repo.delete(source)

  @doc """
  Deletes a source and all associated items, including their stored files in MinIO.
  DB cascade handles items → catalog_items automatically.
  """
  def delete_source_with_storage(%Source{} = source) do
    items = list_items_by_source(source)

    Enum.each(items, fn item ->
      if item.storage_key, do: ScientiaCognita.Storage.delete(item.storage_key)
      if item.processed_key, do: ScientiaCognita.Storage.delete(item.processed_key)
    end)

    Repo.delete(source)
  end

  @doc """
  Resets a source to pending for re-processing. Called by SourceShowLive restart.
  Clears progress counters, pagination state, and error atomically.
  """
  def reset_source(%Source{} = source) do
    source
    |> Ecto.Changeset.change(
      status: "pending",
      pages_fetched: 0,
      total_items: 0,
      next_page_url: nil,
      error: nil
    )
    |> Repo.update()
  end

  def change_source(%Source{} = source, attrs \\ %{}), do: Source.changeset(source, attrs)

  @doc """
  Returns item IDs for `source` that are stuck in an in-progress status
  ("downloading", "processing", "color_analysis", or "render") but have no
  active Oban job — meaning their worker was discarded or cancelled before
  the telemetry handler could mark them as failed.
  """
  def list_stuck_item_ids(%Source{id: source_id}) do
    in_progress_ids =
      Repo.all(
        from i in Item,
          where:
            i.source_id == ^source_id and
              i.status in ["downloading", "processing", "color_analysis", "render"],
          select: i.id
      )

    if in_progress_ids == [] do
      []
    else
      active_item_ids =
        Repo.all(
          from j in "oban_jobs",
            where:
              j.worker in [
                "ScientiaCognita.Workers.DownloadImageWorker",
                "ScientiaCognita.Workers.ProcessImageWorker",
                "ScientiaCognita.Workers.ColorAnalysisWorker",
                "ScientiaCognita.Workers.RenderWorker"
              ] and
                j.state in ["available", "scheduled", "executing", "retryable"] and
                fragment("CAST(json_extract(args, '$.item_id') AS INTEGER)") in ^in_progress_ids,
            select: fragment("CAST(json_extract(args, '$.item_id') AS INTEGER)")
        )
        |> MapSet.new()

      Enum.reject(in_progress_ids, &MapSet.member?(active_item_ids, &1))
    end
  end

  # ---------------------------------------------------------------------------
  # Items
  # ---------------------------------------------------------------------------

  def list_items_by_source(%Source{id: source_id}) do
    Repo.all(from i in Item, where: i.source_id == ^source_id, order_by: [asc: i.inserted_at])
  end

  def list_items_by_source(source_id) when is_integer(source_id) do
    Repo.all(from i in Item, where: i.source_id == ^source_id, order_by: [asc: i.inserted_at])
  end

  @doc """
  Returns ready items for `source_id` together with a MapSet of item IDs
  already present in `catalog_id`, for use in the item-picker UI.
  """
  def list_ready_items_for_picker(source_id, catalog_id) do
    items =
      Repo.all(
        from i in Item,
          where: i.source_id == ^source_id and i.status == "ready",
          order_by: [asc: i.inserted_at]
      )

    in_catalog =
      Repo.all(
        from ci in CatalogItem,
          where: ci.catalog_id == ^catalog_id,
          select: ci.item_id
      )
      |> MapSet.new()

    {items, in_catalog}
  end

  def count_catalog_items(%Catalog{id: catalog_id}) do
    Repo.aggregate(from(ci in CatalogItem, where: ci.catalog_id == ^catalog_id), :count)
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

  def update_item_colors(%Item{} = item, attrs) do
    item
    |> Item.color_changeset(attrs)
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

  @doc """
  Returns the count of items for `source` that are not yet in a terminal state.
  Terminal states are "ready" and "failed". Used by RenderWorker to detect
  when all items have completed and the source can transition to "done".
  """
  def count_items_not_terminal(%Source{id: source_id}) do
    Repo.aggregate(
      from(i in Item,
        where: i.source_id == ^source_id and i.status not in ["ready", "failed"]),
      :count
    )
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

  @doc """
  Returns the processed image URL for the first item in the catalog, or nil.
  Used as the catalog cover image on public listing pages.
  """
  def get_catalog_cover_url(%Catalog{id: catalog_id}) do
    item =
      Repo.one(
        from i in Item,
          join: ci in CatalogItem,
          on: ci.item_id == i.id,
          where: ci.catalog_id == ^catalog_id and not is_nil(i.processed_key),
          order_by: [asc: ci.position, asc: ci.inserted_at],
          limit: 1
      )

    if item, do: ScientiaCognita.Storage.get_url(item.processed_key), else: nil
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
