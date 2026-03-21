defmodule ScientiaCognita.Catalog.GeminiPageResult do
  @moduledoc """
  Embedded schema that captures the full Gemini extraction output for one page.
  One entry is appended to `Source.gemini_pages` per ExtractPageWorker run.
  `items_count` is always derived from `length(raw_items)` — never set independently.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :page_url, :string
    field :is_gallery, :boolean
    field :gallery_title, :string
    field :gallery_description, :string
    field :next_page_url, :string
    field :items_count, :integer
    field :raw_items, {:array, :map}
    field :generated_at, :utc_datetime
  end

  @type t :: %__MODULE__{
          page_url: String.t(),
          is_gallery: boolean(),
          gallery_title: String.t() | nil,
          gallery_description: String.t() | nil,
          next_page_url: String.t() | nil,
          items_count: non_neg_integer(),
          raw_items: [map()],
          generated_at: DateTime.t()
        }

  @spec new(map()) :: t()
  def new(attrs) do
    raw_items = attrs[:raw_items] || []

    %__MODULE__{
      page_url: attrs[:page_url],
      is_gallery: attrs[:is_gallery],
      gallery_title: attrs[:gallery_title],
      gallery_description: attrs[:gallery_description],
      next_page_url: attrs[:next_page_url],
      raw_items: raw_items,
      items_count: length(raw_items),
      generated_at: DateTime.utc_now(:second)
    }
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :page_url,
      :is_gallery,
      :gallery_title,
      :gallery_description,
      :next_page_url,
      :items_count,
      :raw_items,
      :generated_at
    ])
  end
end
