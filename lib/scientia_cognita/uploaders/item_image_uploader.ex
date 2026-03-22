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
