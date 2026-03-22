defmodule ScientiaCognita.Workers.AnalyzeWorker do
  @moduledoc """
  Downloads the thumbnail image, sends it to Gemini for visual analysis,
  stores the result as `image_analysis` on the item, and enqueues ResizeWorker.

  The analysis includes:
    - text_color: optimal overlay text color
    - bg_color: optimal overlay background color
    - bg_opacity: float between 0.60 and 0.85
    - subject: text description of the main subject / origin point

  Args: %{item_id: integer}
  """

  use Oban.Worker, queue: :process, max_attempts: 5

  require Logger

  alias ScientiaCognita.{Catalog, Repo}
  alias ScientiaCognita.Workers.ResizeWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)
  @uploader Application.compile_env(
              :scientia_cognita,
              :uploader_module,
              ScientiaCognita.Uploaders.ItemImageUploader
            )

  @default_analysis %{
    "text_color" => "#FFFFFF",
    "bg_color" => "#000000",
    "bg_opacity" => 0.75,
    "subject" => nil
  }

  @analysis_schema %{
    type: "OBJECT",
    properties: %{
      text_color: %{type: "STRING", enum: ["#FFFFFF", "#1A1A1A"]},
      bg_color: %{type: "STRING"},
      bg_opacity: %{type: "NUMBER"},
      subject: %{type: "STRING"}
    },
    required: ["text_color", "bg_color", "bg_opacity", "subject"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[AnalyzeWorker] item=#{item_id}")

    with {:ok, thumb_binary} <- download_thumbnail(item),
         analysis = analyze_image(thumb_binary),
         {:ok, item} <- fsm_transition(item, "resize", %{image_analysis: analysis}) do
      broadcast(item.source_id, {:item_updated, item})
      %{item_id: item_id} |> ResizeWorker.new() |> Oban.insert()
      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("[AnalyzeWorker] invalid transition for item=#{item_id}")
        :ok

      {:error, reason} ->
        Logger.error("[AnalyzeWorker] failed item=#{item_id}: #{inspect(reason)}")
        item = Catalog.get_item!(item_id)
        {:ok, _} = fsm_transition(item, "failed", %{error: inspect(reason)})
        broadcast(item.source_id, {:item_updated, Catalog.get_item!(item_id)})
        :ok
    end
  rescue
    e ->
      Logger.error("[AnalyzeWorker] exception item=#{item_id}: #{inspect(e)}")

      try do
        fresh = Catalog.get_item!(item_id)
        {:ok, failed} = fsm_transition(fresh, "failed", %{error: inspect(e)})
        broadcast(failed.source_id, {:item_updated, failed})
      rescue
        _ -> :ok
      end

      :ok
  end

  defp download_thumbnail(%{thumbnail_image: nil}), do: {:error, "item has no thumbnail_image"}

  defp download_thumbnail(item) do
    url = @uploader.url({item.thumbnail_image, item})

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp analyze_image(thumb_binary) do
    prompt = """
    Analyze this image and return:
    - text_color: "#FFFFFF" for dark images, "#1A1A1A" for light images
    - bg_color: a hex color that contrasts well with the image content
    - bg_opacity: a float between 0.60 and 0.85
    - subject: a short description of the main subject or focal point depicted
    """

    case @gemini.generate_structured_with_image(prompt, thumb_binary, @analysis_schema, []) do
      {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _, "subject" => _} = result} ->
        result

      _ ->
        @default_analysis
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

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
