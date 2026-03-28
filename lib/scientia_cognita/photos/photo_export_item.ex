defmodule ScientiaCognita.Photos.PhotoExportItem do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending uploaded failed removing)

  schema "photo_export_items" do
    field :status, :string, default: "pending"
    field :error, :string
    field :google_photos_media_id, :string

    belongs_to :photo_export, ScientiaCognita.Photos.PhotoExport
    belongs_to :item, ScientiaCognita.Catalog.Item

    timestamps(type: :utc_datetime)
  end

  def changeset(export_item, attrs) do
    export_item
    |> cast(attrs, [:photo_export_id, :item_id, :status, :error, :google_photos_media_id])
    |> validate_required([:photo_export_id, :item_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:photo_export_id, :item_id])
  end
end
