defmodule ScientiaCognita.Catalog.Item do
  @moduledoc """
  Item schema with fsmx state machine.

  State transitions:
    pending → downloading → thumbnail → analyze → resize → render → ready
    any non-terminal → failed
    any non-terminal → discarded
    discarded → pending (retry)

  The analyze step performs both image analysis (colors, subject) and portrait
  rotation in a single Gemini call.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ScientiaCognita.Catalog.{Source, Catalog, CatalogItem}

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "pending" => ["downloading", "failed", "discarded"],
      "downloading" => ["thumbnail", "failed", "discarded"],
      "thumbnail" => ["analyze", "failed", "discarded"],
      "analyze" => ["resize", "failed", "discarded"],
      "resize" => ["render", "failed", "discarded"],
      "render" => ["ready", "failed", "discarded"],
      "discarded" => ["pending"]
    }

  alias ScientiaCognita.Uploaders.ItemImageUploader

  @statuses ~w(pending downloading thumbnail analyze resize render ready failed discarded)

  @type status :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t(),
          description: String.t() | nil,
          author: String.t() | nil,
          copyright: String.t() | nil,
          original_url: String.t() | nil,
          original_image: term() | nil,
          processed_image: term() | nil,
          thumbnail_image: term() | nil,
          final_image: term() | nil,
          image_analysis: map() | nil,
          status: status(),
          error: String.t() | nil,
          source_id: integer() | nil,
          source: Source.t() | Ecto.Association.NotLoaded.t(),
          catalogs: [Catalog.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "items" do
    field :title, :string
    field :description, :string
    field :author, :string
    field :copyright, :string
    field :original_url, :string
    field :original_image, ItemImageUploader.Type
    field :processed_image, ItemImageUploader.Type
    field :thumbnail_image, ItemImageUploader.Type
    field :final_image, ItemImageUploader.Type
    field :image_analysis, :map
    field :manual_rotation, :string
    field :status, :string, default: "pending"
    field :error, :string

    # Legacy color fields — no longer written by the new pipeline.
    # Kept so existing DB rows and old code don't break.
    field :text_color, :string
    field :bg_color, :string
    field :bg_opacity, :float

    belongs_to :source, Source
    many_to_many :catalogs, Catalog, join_through: CatalogItem

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @rotations ~w(none clockwise counterclockwise)

  def rotations, do: @rotations

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :description, :author, :copyright, :original_url, :manual_rotation, :source_id])
    |> validate_required([:title, :source_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:manual_rotation, @rotations, allow_nil: true)
    |> assoc_constraint(:source)
    |> normalise_manual_rotation()
  end

  defp normalise_manual_rotation(changeset) do
    case get_change(changeset, :manual_rotation) do
      "" -> put_change(changeset, :manual_rotation, nil)
      _ -> changeset
    end
  end

  @doc "Used by Catalog.update_item_status/3 for fixture/test setup only."
  def status_changeset(item, status, opts \\ []) do
    item
    |> change(status: status)
    |> then(fn cs ->
      if Keyword.has_key?(opts, :error),
        do: put_change(cs, :error, opts[:error]),
        else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Used by Catalog.update_item_storage/2 for fixture setup."
  def storage_changeset(item, attrs) do
    item
    |> cast(attrs, [:original_image, :processed_image, :thumbnail_image, :final_image])
  end

  @doc "Used by Catalog.update_item_colors/2 for fixture setup (legacy)."
  def color_changeset(item, attrs) do
    item
    |> cast(attrs, [:text_color, :bg_color, :bg_opacity])
    |> validate_required([:text_color, :bg_color, :bg_opacity])
  end

  # ---------------------------------------------------------------------------
  # fsmx transition_changeset callbacks
  # ---------------------------------------------------------------------------

  def transition_changeset(changeset, "pending", "downloading", _params), do: changeset

  def transition_changeset(changeset, "downloading", "thumbnail", params) do
    changeset
    |> cast(params, [:original_image])
    |> validate_required([:original_image])
    |> put_change(:error, nil)
  end

  def transition_changeset(changeset, "thumbnail", "analyze", params) do
    changeset
    |> cast(params, [:thumbnail_image])
    |> validate_required([:thumbnail_image])
  end

  def transition_changeset(changeset, "analyze", "resize", params) do
    changeset
    |> cast(params, [:image_analysis])
    |> validate_required([:image_analysis])
  end

  def transition_changeset(changeset, "resize", "render", params) do
    changeset
    |> cast(params, [:processed_image])
    |> validate_required([:processed_image])
  end

  def transition_changeset(changeset, "render", "ready", params) do
    changeset
    |> cast(params, [:final_image])
    |> put_change(:error, nil)
  end

  def transition_changeset(changeset, _old, "failed", params) do
    changeset
    |> cast(params, [:error])
    |> validate_required([:error])
  end

  def transition_changeset(changeset, _old, "discarded", params) do
    changeset
    |> cast(params, [:error])
  end

  def transition_changeset(changeset, "discarded", "pending", _params) do
    changeset
    |> put_change(:error, nil)
  end
end
