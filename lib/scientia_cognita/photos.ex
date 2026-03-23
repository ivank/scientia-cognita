defmodule ScientiaCognita.Photos do
  @moduledoc """
  Context for tracking per-user Google Photos export state.

  All functions are scoped to the authenticated user — never expose
  PhotoExport records across users.
  """

  import Ecto.Query

  alias ScientiaCognita.Repo
  alias ScientiaCognita.Photos.{PhotoExport, PhotoExportItem}

  @doc "Returns the user's export for this catalog, or nil."
  def get_export_for_user(user, catalog) do
    Repo.get_by(PhotoExport, user_id: user.id, catalog_id: catalog.id)
  end

  @doc "Returns the existing export, or inserts a new pending one."
  def get_or_create_export(user, catalog) do
    case get_export_for_user(user, catalog) do
      nil ->
        %PhotoExport{}
        |> PhotoExport.changeset(%{user_id: user.id, catalog_id: catalog.id, status: "pending"})
        |> Repo.insert()

      export ->
        {:ok, export}
    end
  end

  @doc """
  Updates the export's status. Pass optional keyword args to also update
  :album_id, :album_url, or :error at the same time.

  ## Examples

      set_export_status(export, "running")
      set_export_status(export, "done", album_url: url, album_id: id)
      set_export_status(export, "failed", error: "token expired")
  """
  def set_export_status(export, status, opts \\ []) do
    attrs = opts |> Enum.into(%{}) |> Map.put(:status, to_string(status))

    export
    |> PhotoExport.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns a list of item IDs that have been confirmed uploaded to Google Photos."
  def list_uploaded_item_ids(export) do
    Repo.all(
      from pei in PhotoExportItem,
        where: pei.photo_export_id == ^export.id and pei.status == "uploaded",
        select: pei.item_id
    )
  end

  @doc "Marks an item as successfully added to the Google Photos album (upsert)."
  def set_item_uploaded(export, item) do
    upsert_export_item(export, item, %{status: "uploaded", error: nil})
  end

  @doc "Records an upload failure for an item (upsert — safe to call multiple times)."
  def set_item_failed(export, item, error) do
    upsert_export_item(export, item, %{status: "failed", error: to_string(error)})
  end

  @doc """
  Returns a map of %{item_id => %{status: s, error: e}} for all tracked items
  in this export. Used by the LiveView to render error badges on the photo grid.
  """
  def list_export_item_statuses(export) do
    Repo.all(
      from pei in PhotoExportItem,
        where: pei.photo_export_id == ^export.id,
        select: {pei.item_id, %{status: pei.status, error: pei.error}}
    )
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp upsert_export_item(export, item, attrs) do
    base = %{photo_export_id: export.id, item_id: item.id}

    %PhotoExportItem{}
    |> PhotoExportItem.changeset(Map.merge(base, attrs))
    |> Repo.insert(
      on_conflict: {:replace, [:status, :error, :updated_at]},
      conflict_target: [:photo_export_id, :item_id]
    )
  end
end
