defmodule ScientiaCognita.Catalog.Catalog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "catalogs" do
    field :name, :string
    field :description, :string
    field :slug, :string

    many_to_many :items, ScientiaCognita.Catalog.Item,
      join_through: ScientiaCognita.Catalog.CatalogItem

    timestamps(type: :utc_datetime)
  end

  def changeset(catalog, attrs) do
    catalog
    |> cast(attrs, [:name, :description, :slug])
    |> validate_required([:name])
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, slugify(name))
        end

      _ ->
        update_change(changeset, :slug, &slugify/1)
    end
  end

  defp slugify(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
