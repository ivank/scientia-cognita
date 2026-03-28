defmodule ScientiaCognita.Uploaders.ItemImageUploader do
  @moduledoc """
  Waffle uploader for item images.
  All three pipeline stages (original, processed, final) use this uploader.
  Files are stored at items/{item_id}/{filename}.
  """

  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]

  def storage_dir(_version, {_file, item}), do: "items/#{item.id}"
  def acl(_version, _), do: :public_read

  @doc """
  Returns the URL for a file with a cache-busting `?v=` query param derived
  from the item's `updated_at` timestamp. Use this for `final_image`, which
  is overwritten in-place on every re-render.
  """
  def url_busted({file, item}) do
    base = url({file, item})
    ts = item.updated_at && DateTime.to_unix(item.updated_at)
    if ts, do: "#{base}?v=#{ts}", else: base
  end

  def bucket do
    Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
  end

  @doc """
  Ensures the configured S3 bucket exists, creating it if not.
  Called at application startup (moved from the deleted Storage module).
  """
  def ensure_bucket_exists do
    b = bucket()

    case ExAws.S3.head_bucket(b) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        b
        |> ExAws.S3.put_bucket("us-east-1")
        |> ExAws.request()
        |> case do
          {:ok, _} -> :ok
          error -> error
        end

      error ->
        error
    end
  end
end
