defmodule ScientiaCognita.Workers.ColorAnalysisWorker do
  @moduledoc """
  Downloads the processed image, generates a thumbnail, asks Gemini for optimal
  text overlay colors, stores them on the item, and enqueues RenderWorker.

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 5

  require Logger

  alias ScientiaCognita.{Catalog, Repo}
  alias ScientiaCognita.Workers.RenderWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)
  @uploader Application.compile_env(:scientia_cognita, :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader)

  @default_colors %{"text_color" => "#FFFFFF", "bg_color" => "#000000", "bg_opacity" => 0.75}

  @color_schema %{
    type: "OBJECT",
    properties: %{
      text_color: %{type: "STRING", enum: ["#FFFFFF", "#1A1A1A"]},
      bg_color: %{type: "STRING"},
      bg_opacity: %{type: "NUMBER"}
    },
    required: ["text_color", "bg_color", "bg_opacity"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[ColorAnalysisWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, thumb_binary} <- make_thumbnail(img),
         colors = get_colors(thumb_binary),
         {:ok, item} <-
           fsm_transition(item, "render", %{
             text_color: colors["text_color"],
             bg_color: colors["bg_color"],
             bg_opacity: colors["bg_opacity"]
           }) do
      broadcast(item.source_id, {:item_updated, item})
      %{item_id: item_id} |> RenderWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[ColorAnalysisWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ColorAnalysisWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  rescue
    e ->
      Logger.error("[ColorAnalysisWorker] exception item=#{item_id}: #{inspect(e)}")
      try do
        fresh = Catalog.get_item!(item_id)
        {:ok, failed} = fsm_transition(fresh, "failed", %{error: inspect(e)})
        broadcast(failed.source_id, {:item_updated, failed})
      rescue
        _ -> :ok
      end
      :ok
  end

  defp fsm_transition(schema, new_state, params) do
    Ecto.Multi.new()
    |> Fsmx.transition_multi(schema, :transition, new_state, params, state_field: :status)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: updated}} ->
        {:ok, updated}

      {:error, :transition, %Ecto.Changeset{} = cs, _} ->
        if Keyword.has_key?(cs.errors, :status) do
          {:error, :invalid_transition}
        else
          {:error, cs}
        end

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp download_processed(%{processed_image: nil}), do: {:error, "item has no processed_image"}

  defp download_processed(item) do
    url = @uploader.url({item.processed_image, item})

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp make_thumbnail(img) do
    with {:ok, thumb} <- Image.thumbnail(img, 200, height: 200, crop: :center) do
      Image.write(thumb, :memory, suffix: ".jpg", quality: 70)
    end
  end

  defp get_colors(thumb_binary) do
    prompt = """
    Analyze this image and choose colors for a semi-transparent text overlay banner
    placed at the bottom of a 1920×1080 photo.

    - text_color: "#FFFFFF" for dark images, "#1A1A1A" for light images
    - bg_color: a hex color that contrasts well with the image content
    - bg_opacity: a float between 0.60 and 0.85
    """

    case @gemini.generate_structured_with_image(prompt, thumb_binary, @color_schema, []) do
      {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _} = colors} -> colors
      _ -> @default_colors
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
