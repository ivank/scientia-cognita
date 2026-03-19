defmodule ScientiaCognita.Catalog.CatalogItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "catalog_items" do
    field :position, :integer, default: 0

    belongs_to :catalog, ScientiaCognita.Catalog.Catalog
    belongs_to :item, ScientiaCognita.Catalog.Item

    timestamps(type: :utc_datetime)
  end

  def changeset(catalog_item, attrs) do
    catalog_item
    |> cast(attrs, [:catalog_id, :item_id, :position])
    |> validate_required([:catalog_id, :item_id])
    |> assoc_constraint(:catalog)
    |> assoc_constraint(:item)
    |> unique_constraint([:catalog_id, :item_id], name: :catalog_items_catalog_id_item_id_index)
  end
end
