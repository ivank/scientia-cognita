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

  # Waffle's default_host/2 hardcodes s3.amazonaws.com and ignores ExAws config.
  # Override asset_host/0 to build the URL base from the ExAws S3 config so that
  # both MinIO (dev) and Tigris (prod) generate correct public URLs.
  # Returns scheme+host[:port]/bucket — Waffle appends the object key after this.
  def asset_host do
    s3 = Application.get_env(:ex_aws, :s3, [])
    scheme = s3[:scheme] || "https://"
    host = s3[:host] || "s3.amazonaws.com"

    base =
      case s3[:port] do
        nil -> "#{scheme}#{host}"
        port -> "#{scheme}#{host}:#{port}"
      end

    "#{base}/#{bucket()}"
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
