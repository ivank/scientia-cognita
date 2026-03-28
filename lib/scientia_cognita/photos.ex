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

  @doc "Fetches an export by ID, raising if not found."
  def get_export!(id), do: Repo.get!(PhotoExport, id)

  @doc "Returns the existing export, or inserts a new pending one. Race-safe via on_conflict."
  def get_or_create_export(user, catalog) do
    attrs = %{user_id: user.id, catalog_id: catalog.id, status: "pending"}
    changeset = PhotoExport.changeset(%PhotoExport{}, attrs)

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, %PhotoExport{id: nil}} ->
        # Conflict — row already existed (concurrent insert); fetch and return it
        {:ok, get_export_for_user(user, catalog)}

      {:ok, export} ->
        {:ok, export}

      {:error, _} = error ->
        error
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

  @doc "Marks an item as successfully added to the Google Photos album (upsert). Stores optional media_id."
  def set_item_uploaded(export, item, media_id \\ nil) do
    upsert_export_item(export, item, %{
      status: "uploaded",
      error: nil,
      google_photos_media_id: media_id
    })
  end

  @doc "Records an upload failure for an item (upsert — safe to call multiple times)."
  def set_item_failed(export, item, error) do
    upsert_export_item(export, item, %{status: "failed", error: to_string(error)})
  end

  @doc "Marks an item as being removed from the album (upsert)."
  def set_item_removing(export, item) do
    upsert_export_item(export, item, %{status: "removing", error: nil})
  end

  @doc "Returns the PhotoExportItem for a given export and item, or nil."
  def get_export_item(export, item) do
    Repo.get_by(PhotoExportItem, photo_export_id: export.id, item_id: item.id)
  end

  @doc "Deletes the PhotoExportItem record for the given export and item."
  def delete_export_item(export, item) do
    case get_export_item(export, item) do
      nil -> {:ok, nil}
      record -> Repo.delete(record)
    end
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

  @doc "Freshly reloads the export from the DB. Use in workers to check for cancellation."
  def reload_export(%PhotoExport{id: id}), do: Repo.get!(PhotoExport, id)

  @doc "Sets the export status to cancelled, stopping any in-progress worker."
  def cancel_export(export), do: set_export_status(export, "cancelled")

  @doc "Deletes the local PhotoExport record without making any Google Photos API call."
  def delete_local_only(export), do: Repo.delete(export)

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp upsert_export_item(export, item, attrs) do
    base = %{photo_export_id: export.id, item_id: item.id}

    %PhotoExportItem{}
    |> PhotoExportItem.changeset(Map.merge(base, attrs))
    |> Repo.insert(
      on_conflict: {:replace, [:status, :error, :google_photos_media_id, :updated_at]},
      conflict_target: [:photo_export_id, :item_id]
    )
  end
end
