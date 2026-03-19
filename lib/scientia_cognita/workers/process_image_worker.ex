defmodule ScientiaCognita.Workers.ProcessImageWorker do
  @moduledoc """
  Creates a 16:9 Full HD (1920×1080) processed variant of an item's image:
  1. Downloads original from MinIO
  2. Generates a 200px thumbnail → asks Gemini for best text/bg colors
  3. Resizes & crops source image to 1920×1080
  4. Renders description + author + copyright as a semi-transparent overlay band
  5. Uploads to MinIO, marks item as "ready"

  Args: %{item_id: integer}
  """

  use Oban.Worker,
    queue: :process,
    max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, Gemini, Storage}

  @target_width 1920
  @target_height 1080
  @band_height 280
  @default_colors %{"text_color" => "#FFFFFF", "bg_color" => "#000000", "bg_opacity" => 0.75}

  # Structured output schema for color analysis.
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

    Logger.info("[ProcessImageWorker] item=#{item_id}")

    with {:ok, original_binary} <- download_original(item.storage_key),
         {:ok, img} <- Image.from_binary(original_binary),
         {:ok, thumb_binary} <- make_thumbnail(img),
         colors = get_gemini_colors(thumb_binary),
         {:ok, composed} <- compose_image(img, item, colors),
         {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
         processed_key = Storage.item_key(item.id, :processed, ".jpg"),
         {:ok, _} <- Storage.upload(processed_key, output_binary, content_type: "image/jpeg"),
         {:ok, item} <- Catalog.update_item_storage(item, %{processed_key: processed_key}),
         {:ok, _} <- Catalog.update_item_status(item, "ready") do
      broadcast(item.source_id, {:item_updated, item})
      :ok
    else
      {:error, reason} ->
        Logger.error("[ProcessImageWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = Catalog.update_item_status(item, "failed", error: inspect(reason))
        broadcast(item.source_id, {:item_updated, item})
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Image processing
  # ---------------------------------------------------------------------------

  defp download_original(nil), do: {:error, "item has no storage_key"}

  defp download_original(storage_key) do
    url = Storage.get_url(storage_key)

    case Req.get(url, receive_timeout: 30_000) do
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

  defp get_gemini_colors(thumb_binary) do
    prompt = """
    Analyze this image and choose colors for a semi-transparent text overlay banner
    placed at the bottom of a 1920×1080 photo.

    - text_color: "#FFFFFF" for dark images, "#1A1A1A" for light images
    - bg_color: a hex color that contrasts well with the image content
    - bg_opacity: a float between 0.60 and 0.85
    """

    case Gemini.generate_structured_with_image(prompt, thumb_binary, @color_schema) do
      {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _} = colors} -> colors
      _ -> @default_colors
    end
  end

  defp compose_image(img, item, colors) do
    with {:ok, base} <- resize_to_fill(img) do
      overlay_text = build_overlay_text(item)
      render_text_overlay(base, overlay_text, colors)
    end
  end

  defp resize_to_fill(img) do
    # thumbnail with crop fills the bounding box exactly
    Image.thumbnail(img, @target_width, height: @target_height, crop: :center)
  end

  defp render_text_overlay(base, text, colors) do
    text_color = Map.get(colors, "text_color", "#FFFFFF")
    bg_color = Map.get(colors, "bg_color", "#000000")
    bg_opacity = Map.get(colors, "bg_opacity", 0.75)

    text_opts = [
      font_size: 28,
      font_weight: :normal,
      text_fill_color: text_color,
      background_fill_color: bg_color,
      background_fill_opacity: bg_opacity,
      width: @target_width - 120,
      padding: [60, 30],
      align: :left
    ]

    with {:ok, text_img} <- Image.Text.text(text, text_opts) do
      text_height = Image.height(text_img)
      y_pos = @target_height - text_height

      Image.compose(base, text_img, x: 0, y: max(y_pos, @target_height - @band_height))
    end
  end

  defp build_overlay_text(item) do
    parts =
      [
        item.description,
        item.author && "© #{item.author}",
        item.copyright
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(String.trim(&1) == ""))

    case parts do
      [] -> item.title || ""
      _ -> Enum.join(parts, "\n")
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
