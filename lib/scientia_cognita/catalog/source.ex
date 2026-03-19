defmodule ScientiaCognita.Catalog.Source do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending running done failed)

  schema "sources" do
    field :url, :string
    field :name, :string
    field :status, :string, default: "pending"
    field :next_page_url, :string
    field :pages_fetched, :integer, default: 0
    field :total_items, :integer, default: 0
    field :error, :string

    has_many :items, ScientiaCognita.Catalog.Item

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:url, :name, :status, :next_page_url, :pages_fetched, :total_items, :error])
    |> validate_required([:url, :name])
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint(:url)
  end

  def status_changeset(source, status, opts \\ []) do
    source
    |> change(status: status)
    |> then(fn cs ->
      if error = opts[:error], do: put_change(cs, :error, error), else: cs
    end)
    |> validate_inclusion(:status, @statuses)
  end

  def progress_changeset(source, attrs) do
    source
    |> cast(attrs, [:next_page_url, :pages_fetched, :total_items])
  end
end
