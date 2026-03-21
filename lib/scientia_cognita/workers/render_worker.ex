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

  alias ScientiaCognita.{Catalog, Repo, Storage}

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @storage Application.compile_env(:scientia_cognita, :storage_module, ScientiaCognita.Storage)

  @band_height_ratio 0.259

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[RenderWorker] item=#{item_id}")

    with {:ok, binary} <- download_processed(item.processed_key),
         {:ok, img} <- Image.from_binary(binary),
         {:ok, composed} <- compose_image(img, item),
         {:ok, output_binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 85),
         final_key = Storage.item_key(item.id, :final, ".jpg"),
         {:ok, _} <- @storage.upload(final_key, output_binary, content_type: "image/jpeg"),
         {:ok, item} <- fsm_transition(item, "ready", %{processed_key: final_key}) do
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

  defp download_processed(nil), do: {:error, "item has no processed_key"}

  defp download_processed(key) do
    case @http.get(Storage.get_url(key), receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp compose_image(img, item) do
    text_color = item.text_color || "#FFFFFF"
    bg_color = item.bg_color || "#000000"
    bg_opacity = item.bg_opacity || 0.75
    overlay_text = build_overlay_text(item)

    img_width = Image.width(img)
    img_height = Image.height(img)
    padding_x = max(trunc(img_width * 0.031), 4)
    text_width = max(img_width - padding_x * 2, 10)
    font_size = max(trunc(img_height * 0.026), 8)
    band_height = max(trunc(img_height * @band_height_ratio), 10)

    text_opts = [
      font_size: font_size,
      font_weight: :normal,
      text_fill_color: text_color,
      background_fill_color: bg_color,
      background_fill_opacity: bg_opacity,
      width: text_width,
      padding: [padding_x, max(trunc(img_height * 0.028), 4)],
      align: :left
    ]

    with {:ok, text_img} <- Image.Text.text(overlay_text, text_opts) do
      text_height = Image.height(text_img)
      y_pos = img_height - text_height
      Image.compose(img, text_img, x: 0, y: max(y_pos, img_height - band_height))
    end
  end

  defp build_overlay_text(item) do
    [item.description, item.author && "© #{item.author}", item.copyright]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> case do
      [] -> item.title || ""
      parts -> Enum.join(parts, "\n")
    end
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
