defmodule ScientiaCognita.Storage do
  @moduledoc """
  S3-compatible object storage via ExAws (MinIO in development, S3 in production).
  All keys are relative to the configured bucket.
  """

  @doc "Returns the configured bucket name."
  def bucket do
    Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
  end

  @doc """
  Uploads binary content under `key`.
  Returns `{:ok, key}` on success.
  """
  def upload(key, binary, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    ExAws.S3.put_object(bucket(), key, binary,
      content_type: content_type,
      acl: :public_read
    )
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the public URL for `key`.
  Constructs the URL from the ExAws S3 config (host/port/scheme).
  """
  def get_url(key) do
    s3_cfg = Application.get_env(:ex_aws, :s3, [])
    scheme = Keyword.get(s3_cfg, :scheme, "https://")
    host = Keyword.get(s3_cfg, :host, "s3.amazonaws.com")

    case Keyword.get(s3_cfg, :port) do
      nil -> "#{scheme}#{host}/#{bucket()}/#{key}"
      port -> "#{scheme}#{host}:#{port}/#{bucket()}/#{key}"
    end
  end

  @doc "Deletes the object at `key`. Returns `:ok` or `{:error, reason}`."
  def delete(key) do
    ExAws.S3.delete_object(bucket(), key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Ensures the configured bucket exists, creating it if necessary.
  Safe to call at startup or in seeds.
  """
  def ensure_bucket_exists do
    case ExAws.S3.head_bucket(bucket()) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        bucket()
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

  @doc """
  Generates a unique storage key for an item's image.

      iex> Storage.item_key(42, :original, ".jpg")
      "items/42/original.jpg"
  """
  def item_key(item_id, variant, ext) when variant in [:original, :processed] do
    "items/#{item_id}/#{variant}#{ext}"
  end
end
