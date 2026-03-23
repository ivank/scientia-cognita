defmodule ScientiaCognita.Photos.PhotoExport do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending running done failed deleted)

  schema "photo_exports" do
    field :album_id, :string
    field :album_url, :string
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :user, ScientiaCognita.Accounts.User
    belongs_to :catalog, ScientiaCognita.Catalog.Catalog

    has_many :photo_export_items, ScientiaCognita.Photos.PhotoExportItem

    timestamps(type: :utc_datetime)
  end

  def changeset(export, attrs) do
    export
    |> cast(attrs, [:user_id, :catalog_id, :album_id, :album_url, :status, :error])
    |> validate_required([:user_id, :catalog_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :catalog_id])
  end
end
