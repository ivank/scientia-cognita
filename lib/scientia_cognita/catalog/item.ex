defmodule ScientiaCognita.Catalog.Item do
  @moduledoc """
  Item schema with fsmx state machine.

  State transitions:
    pending → downloading → processing → color_analysis → render → ready
    any non-terminal → failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ScientiaCognita.Catalog.{Source, Catalog, CatalogItem}

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "pending" => ["downloading", "failed"],
      "downloading" => ["processing", "failed"],
      "processing" => ["color_analysis", "failed"],
      "color_analysis" => ["render", "failed"],
      "render" => ["ready", "failed"]
    }

  @statuses ~w(pending downloading processing color_analysis render ready failed)

  @type status :: String.t()
  # valid values: "pending" | "downloading" | "processing" |
  #               "color_analysis" | "render" | "ready" | "failed"

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t(),
          description: String.t() | nil,
          author: String.t() | nil,
          copyright: String.t() | nil,
          original_url: String.t() | nil,
          storage_key: String.t() | nil,
          processed_key: String.t() | nil,
          status: status(),
          error: String.t() | nil,
          text_color: String.t() | nil,
          bg_color: String.t() | nil,
          bg_opacity: float() | nil,
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
    field :storage_key, :string
    field :processed_key, :string
    field :status, :string, default: "pending"
    field :error, :string

    # Set during color_analysis
    field :text_color, :string
    field :bg_color, :string
    field :bg_opacity, :float

    belongs_to :source, Source
    many_to_many :catalogs, Catalog, join_through: CatalogItem

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
    |> cast(attrs, [:storage_key, :processed_key])
  end

  @doc "Used by Catalog.update_item_colors/2 for fixture setup."
  def color_changeset(item, attrs) do
    item
    |> cast(attrs, [:text_color, :bg_color, :bg_opacity])
    |> validate_required([:text_color, :bg_color, :bg_opacity])
  end

  # ---------------------------------------------------------------------------
  # fsmx transition_changeset callbacks
  # ---------------------------------------------------------------------------

  def transition_changeset(changeset, "pending", "downloading", _params), do: changeset

  def transition_changeset(changeset, "downloading", "processing", params) do
    changeset
    |> cast(params, [:storage_key])
    |> validate_required([:storage_key])
    |> put_change(:error, nil)
  end

  def transition_changeset(changeset, "processing", "color_analysis", params) do
    changeset
    |> cast(params, [:processed_key])
    |> validate_required([:processed_key])
  end

  def transition_changeset(changeset, "color_analysis", "render", params) do
    changeset
    |> cast(params, [:text_color, :bg_color, :bg_opacity])
    |> validate_required([:text_color, :bg_color, :bg_opacity])
  end

  # NOTE: spec says "no extra fields required" but we intentionally cast processed_key
  # here so RenderWorker can write the final rendered image path atomically in
  # the render→ready transition, eliminating a separate update_item_storage call.
  def transition_changeset(changeset, "render", "ready", params) do
    changeset
    |> cast(params, [:processed_key])
    |> put_change(:error, nil)
  end

  def transition_changeset(changeset, _old, "failed", params) do
    changeset
    |> cast(params, [:error])
    |> validate_required([:error])
  end
end
