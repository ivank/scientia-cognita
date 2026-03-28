defmodule ScientiaCognita.Workers.RenderWorker do
  @moduledoc """
  Downloads the processed 1920×1080 image, renders a text overlay band
  using the stored Gemini-determined colors, and uploads the final image.
  Marks the item as "ready". When the last item finishes, transitions the
  source from "items_loading" to "done".

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 5

  require Logger

  alias ScientiaCognita.{Catalog, Repo}

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @uploader Application.compile_env(
              :scientia_cognita,
              :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader
            )

  # Pango renders un-breakable text (long URLs, base64 blobs, etc.) as a
  # single line, computing a buffer of tens of gigabytes. Cap each field.
  @max_title_chars 200
  @max_body_chars 400

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[RenderWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, composed} <- compose_image(img, item),
         {:ok, composed} <- compose_watermark(composed),
         {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
         {:ok, file} <- @uploader.store({%{filename: "final.jpg", binary: output_binary}, item}),
         {:ok, item} <-
           fsm_transition(item, "ready", %{final_image: %{file_name: file, updated_at: nil}}) do
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
  rescue
    e ->
      Logger.error("[RenderWorker] exception item=#{item_id}: #{inspect(e)}")

      try do
        fresh = Catalog.get_item!(item_id)
        {:ok, failed} = fsm_transition(fresh, "failed", %{error: inspect(e)})
        broadcast(failed.source_id, {:item_updated, failed})
      rescue
        _ -> :ok
      end

      :ok
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

  defp compose_watermark(img) do
    img_w = Image.width(img)
    img_h = Image.height(img)
    wm_font = max(trunc(img_h * 0.013), 10)
    margin = max(trunc(img_w * 0.012), 10)

    # rotate(-90) makes the +x text direction point downward in screen space.
    # translate(right_x + wm_font, top_y) puts the rotated origin near the top-right corner.
    right_x = img_w - margin - wm_font
    top_y = max(trunc(img_h * 0.16), 20)

    wm_svg =
      %Victor{
        width: img_w,
        height: img_h,
        items: [
          {:text,
           %{
             "font-family" => "Sans",
             "font-size" => wm_font,
             "font-weight" => "300",
             "letter-spacing" => "3",
             "fill" => "#FFFFFF",
             "fill-opacity" => "0.35",
             "transform" => "translate(#{right_x + wm_font}, #{top_y}) rotate(-90)",
             x: 0,
             y: wm_font
           }, "scientia cognita"}
        ]
      }
      |> Victor.get_svg()

    with {:ok, wm} <- Image.from_svg(wm_svg) do
      Image.compose(img, wm, x: 0, y: 0)
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
    analysis = item.image_analysis || %{}
    text_color = analysis["text_color"] || item.text_color || "#FFFFFF"
    bg_color = analysis["bg_color"] || item.bg_color || "#000000"
    bg_opacity = analysis["bg_opacity"] || item.bg_opacity || 0.75

    img_width = Image.width(img)
    img_height = Image.height(img)
    padding_x = max(trunc(img_width * 0.017), 6)
    padding_y = max(trunc(img_height * 0.022), 8)
    body_font = max(trunc(img_height * 0.02), 8)
    title_font = max(trunc(body_font * 1), 10)
    radius = max(trunc(img_height * 0.02), 8)
    # Align with Google Photos album title on Android TV:
    # left margin matches the system UI (~3% width), bottom gap leaves room
    # for the album title bar that appears below our box (~18% height).
    offset_x = max(trunc(img_width * 0.03), 16)
    offset_y = max(trunc(img_height * 0.18), 40)
    inner_width = max(trunc(img_width * 0.94) - padding_x * 2, 20)

    title = truncate(item.title, @max_title_chars)
    body = build_body_text(item)

    svg =
      build_overlay_svg(
        title,
        body,
        text_color,
        bg_color,
        bg_opacity,
        inner_width,
        padding_x,
        padding_y,
        title_font,
        body_font,
        radius
      )

    with {:ok, overlay} <- Image.from_svg(svg) do
      overlay_h = Image.height(overlay)
      y = max(img_height - overlay_h - offset_y, 0)
      Image.compose(img, overlay, x: offset_x, y: y)
    end
  end

  # Builds the text overlay SVG using Victor.
  # Using SVG avoids vips_text/Pango, which computes buffer sizes before allocating
  # and will abort with "out of memory" for text that can't be word-broken.
  # librsvg renders to the exact declared dimensions, so allocation is bounded.
  defp build_overlay_svg(
         title,
         body,
         text_color,
         bg_color,
         bg_opacity,
         inner_width,
         padding_x,
         padding_y,
         title_font,
         body_font,
         radius
       ) do
    lh_title = trunc(title_font * 1.35)
    lh_body = trunc(body_font * 1.35)

    title_lines = svg_wrap(title, title_font, inner_width)
    body_lines = svg_wrap(body, body_font, inner_width)

    gap = if title_lines != [] and body_lines != [], do: trunc(body_font * 0.8), else: 0

    text_height = length(title_lines) * lh_title + gap + length(body_lines) * lh_body

    card_w = inner_width + padding_x * 2
    card_h = max(text_height + padding_y * 2, padding_y * 2 + lh_title)

    rect =
      {:rect,
       %{
         "fill-opacity" => bg_opacity,
         width: card_w,
         height: card_h,
         rx: radius,
         ry: radius,
         fill: bg_color
       }, []}

    title_elements =
      title_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        y = padding_y + title_font + i * lh_title

        {:text,
         %{
           "font-family" => "Sans",
           "font-size" => title_font,
           "font-weight" => "bold",
           x: padding_x,
           y: y,
           fill: text_color
         }, escape_content(line)}
      end)

    body_start_y = padding_y + length(title_lines) * lh_title + gap

    body_elements =
      body_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        y = body_start_y + body_font + i * lh_body

        {:text,
         %{
           "font-family" => "Sans",
           "font-size" => body_font,
           x: padding_x,
           y: y,
           fill: text_color
         }, escape_content(line)}
      end)

    %Victor{width: card_w, height: card_h, items: [rect] ++ title_elements ++ body_elements}
    |> Victor.get_svg()
  end

  # Wraps text into lines at inner_width. Uses avg char width ≈ 0.46 × font_size.
  defp svg_wrap(nil, _fs, _w), do: []
  defp svg_wrap("", _fs, _w), do: []

  defp svg_wrap(text, font_size, max_width) do
    chars_per_line = max(trunc(max_width / (font_size * 0.46)), 10)

    text
    |> String.split("\n")
    |> Enum.flat_map(&word_wrap_line(&1, chars_per_line))
  end

  defp word_wrap_line(line, max_chars) do
    words = String.split(line, " ", trim: true)

    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        candidate = if current == "", do: word, else: current <> " " <> word

        cond do
          String.length(candidate) <= max_chars ->
            {lines, candidate}

          current == "" ->
            # Single word longer than the line limit — emit it as-is
            {[word | lines], ""}

          true ->
            {[current | lines], word}
        end
      end)

    result = if current != "", do: [current | lines], else: lines
    Enum.reverse(result)
  end

  # Escapes < and > before passing to Victor.
  # Victor's get_content/1 handles & → &amp; automatically.
  defp escape_content(nil), do: ""

  defp escape_content(text) do
    text
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp truncate(nil), do: nil

  defp truncate(s, max \\ @max_body_chars) do
    if String.length(s) > max, do: String.slice(s, 0, max) <> "…", else: s
  end

  defp build_body_text(item) do
    [item.description, item.author && "© #{item.author}", item.copyright]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&truncate/1)
    |> Enum.join("\n")
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
