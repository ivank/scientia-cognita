defmodule ScientiaCognita.Catalog.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending downloading processing ready failed)

  schema "items" do
    field :title, :string
    field :description, :string
    field :author, :string
    field :copyright, :string
    field :original_url, :string
    field :storage_key, :string
    field :processed_key, :string
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :source, ScientiaCognita.Catalog.Source
    many_to_many :catalogs, ScientiaCognita.Catalog.Catalog, join_through: ScientiaCognita.Catalog.CatalogItem

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :description, :author, :copyright, :original_url, :source_id])
    |> validate_required([:title, :source_id])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:source)
  end

  def status_changeset(item, status, opts \\ []) do
    item
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:storage_key, :processed_key])
  end
end
