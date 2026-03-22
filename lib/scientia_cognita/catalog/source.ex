defmodule ScientiaCognita.Catalog.Source do
  @moduledoc """
  Source schema with fsmx state machine.

  State transitions:
    pending → fetching → extracting → items_loading → done
    any non-terminal → failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ScientiaCognita.Catalog.{GeminiPageResult, Item}

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "pending" => ["fetching", "failed"],
      "fetching" => ["extracting", "failed"],
      "extracting" => ["extracting", "items_loading", "failed"],
      "items_loading" => ["done", "failed"]
    }

  @statuses ~w(pending fetching extracting items_loading done failed)

  @type status :: String.t()
  # valid values: "pending" | "fetching" | "extracting" | "items_loading" | "done" | "failed"

  @type t :: %__MODULE__{
          id: integer() | nil,
          url: String.t(),
          name: String.t(),
          status: status(),
          title: String.t() | nil,
          description: String.t() | nil,
          copyright: String.t() | nil,
          raw_html: String.t() | nil,
          next_page_url: String.t() | nil,
          pages_fetched: non_neg_integer(),
          total_items: non_neg_integer(),
          error: String.t() | nil,
          gemini_pages: [GeminiPageResult.t()],
          items: [Item.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "sources" do
    field :url, :string
    field :name, :string
    field :status, :string, default: "pending"
    field :next_page_url, :string
    field :pages_fetched, :integer, default: 0
    field :total_items, :integer, default: 0
    field :error, :string
    field :raw_html, :string
    field :title, :string
    field :description, :string
    field :copyright, :string

    embeds_many :gemini_pages, GeminiPageResult, on_replace: :delete

    has_many :items, Item

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :url,
      :name,
      :status,
      :next_page_url,
      :pages_fetched,
      :total_items,
      :error,
      :title,
      :description
    ])
    |> validate_required([:url])
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint(:url)
  end

  @doc "Used by Catalog.update_source_status/3 for fixture/test setup only."
  def status_changeset(source, status, opts \\ []) do
    source
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  # ---------------------------------------------------------------------------
  # fsmx transition_changeset callbacks
  # ---------------------------------------------------------------------------

  def transition_changeset(changeset, "pending", "fetching", _params), do: changeset

  def transition_changeset(changeset, "fetching", "extracting", params) do
    changeset
    |> cast(params, [:raw_html])
    |> validate_required([:raw_html])
  end

  def transition_changeset(changeset, "extracting", "extracting", params) do
    existing = get_field(changeset, :gemini_pages) || []

    changeset
    |> cast(params, [:pages_fetched, :total_items, :next_page_url])
    |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
  end

  def transition_changeset(changeset, "extracting", "items_loading", params) do
    existing = get_field(changeset, :gemini_pages) || []

    changeset
    |> cast(params, [:pages_fetched, :total_items, :title, :description, :copyright])
    |> put_embed(:gemini_pages, existing ++ [params[:gemini_page]])
  end

  def transition_changeset(changeset, "items_loading", "done", _params), do: changeset

  def transition_changeset(changeset, _old, "failed", params) do
    changeset
    |> cast(params, [:error])
    |> validate_required([:error])
  end

  @doc """
  Returns the best human-readable name for a source: explicit name, then
  extracted title, then the URL hostname, then the raw URL as a fallback.
  """
  def display_name(%__MODULE__{} = source) do
    source.name || source.title ||
      case URI.parse(source.url) do
        %URI{host: host} when is_binary(host) -> host
        _ -> source.url
      end
  end
end
