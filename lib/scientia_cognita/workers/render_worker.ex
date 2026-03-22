defmodule ScientiaCognita.Workers.RenderWorker do
  @moduledoc """
  Downloads the processed 1920×1080 image, renders a text overlay band
  using the stored Gemini-determined colors, and uploads the final image.
  Marks the item as "ready". When the last item finishes, transitions the
  source from "items_loading" to "done".

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, Repo}

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @uploader Application.compile_env(:scientia_cognita, :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[RenderWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, composed} <- compose_image(img, item),
         {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
         {:ok, file} <- @uploader.store({%{binary: output_binary, file_name: "final.jpg"}, item}),
         {:ok, item} <- fsm_transition(item, "ready", %{final_image: %{file_name: file, updated_at: nil}}) do
      broadcast(item.source_id, {:item_updated, item})
      maybe_complete_source(item)
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[RenderWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[RenderWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  end

  defp maybe_complete_source(item) do
    source = Catalog.get_source!(item.source_id)

    if source.status == "items_loading" do
      pending_count = Catalog.count_items_not_terminal(source)

      if pending_count == 0 do
        multi =
          Ecto.Multi.new()
          |> Fsmx.transition_multi(source, :transition, "done", %{}, state_field: :status)

        case Repo.transaction(multi) do
          {:ok, %{transition: done_source}} ->
            broadcast(item.source_id, {:source_updated, done_source})

          {:error, :transition, %Ecto.Changeset{} = _cs, _} ->
            # Race: another RenderWorker or a concurrent failure already closed the source
            :ok

          {:error, _, reason, _} ->
            Logger.error(
              "[RenderWorker] failed to close source=#{item.source_id}: #{inspect(reason)}"
            )
        end
      end
    end
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
    case @http.get(@uploader.url({item.processed_image, item}), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp compose_image(img, item) do
    text_color = item.text_color || "#FFFFFF"
    bg_color = item.bg_color || "#000000"
    bg_opacity = item.bg_opacity || 0.75

    img_width = Image.width(img)
    img_height = Image.height(img)
    padding_x = max(trunc(img_width * 0.03), 8)
    padding_y = max(trunc(img_height * 0.025), 6)
    body_font = max(trunc(img_height * 0.02), 8)
    title_font = max(trunc(body_font * 1), 10)
    radius = max(trunc(img_height * 0.045), 14)
    # Align with Google Photos album title on Android TV:
    # left margin matches the system UI (~5% width), bottom gap leaves room
    # for the album title bar that appears below our box (~13% height).
    offset_x = max(trunc(img_width * 0.05), 16)
    offset_y = max(trunc(img_height * 0.13), 40)
    inner_width = max(trunc(img_width * 0.85) - padding_x * 2, 20)

    title = item.title
    body = build_body_text(item)

    pango_text = build_pango_markup(title, body, title_font, body_font)

    with {:ok, text_img} <-
           Image.Text.text({:safe, pango_text},
             width: inner_width,
             text_fill_color: text_color,
             align: :left
           ),
         text_w = Image.width(text_img),
         text_h = Image.height(text_img),
         card_w = text_w + padding_x * 2,
         card_h = text_h + padding_y * 2,
         {:ok, bg_img} <- rounded_rect(card_w, card_h, radius, bg_color, bg_opacity),
         {:ok, overlay} <- Image.compose(bg_img, text_img, x: padding_x, y: padding_y) do
      overlay_h = Image.height(overlay)
      y = max(img_height - overlay_h - offset_y, 0)
      Image.compose(img, overlay, x: offset_x, y: y)
    end
  end

  # Renders title (bold, larger) and body as a single Pango markup string.
  # A small-font spacer line between them creates a visible margin.
  # text_fill_color is applied as a flat layer by Image.Text so no color markup needed.
  defp build_pango_markup(nil, "", _tf, _bf), do: " "

  defp build_pango_markup(nil, body, _tf, bf),
    do: ~s(<span font="Sans #{bf}">#{xml_escape(body)}</span>)

  defp build_pango_markup(title, "", tf, _bf),
    do: ~s(<span font="Sans Bold #{tf}">#{xml_escape(title)}</span>)

  defp build_pango_markup(title, body, tf, bf) do
    gap_font = max(trunc(bf * 0.5), 4)

    [
      ~s(<span font="Sans Bold #{tf}">#{xml_escape(title)}</span>),
      ~s(<span font="Sans #{gap_font}"> </span>),
      ~s(<span font="Sans #{bf}">#{xml_escape(body)}</span>)
    ]
    |> Enum.join("\n")
  end

  defp xml_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp rounded_rect(width, height, radius, color, opacity) do
    svg = """
    <svg width="#{width}" height="#{height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="#{width}" height="#{height}" rx="#{radius}" ry="#{radius}"
            fill="#{color}" fill-opacity="#{opacity}" />
    </svg>
    """

    Image.from_svg(svg)
  end

  defp build_body_text(item) do
    [item.description, item.author && "© #{item.author}", item.copyright]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n")
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
