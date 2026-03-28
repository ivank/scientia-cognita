defmodule ScientiaCognita.Workers.AnalyzeWorker do
  @moduledoc """
  Downloads the original image, sends it to Gemini for combined visual analysis
  and (for portrait images) rotation detection, applies any needed rotation,
  and enqueues ResizeWorker.

  For landscape images (width ≥ height): one Gemini call for analysis only;
  rotation is set to "none" without consulting Gemini.

  For portrait images (height > width): one Gemini call with a combined schema
  that returns both the analysis fields and the rotation decision. The image is
  rotated and re-uploaded as original_image when Gemini returns "clockwise" or
  "counterclockwise".

  The analysis stored in image_analysis includes:
    - text_color: optimal overlay text color (#FFFFFF or #1A1A1A)
    - bg_color: hex color sampled from the image for the overlay background
    - bg_opacity: float between 0.60 and 0.85
    - subject: one-sentence focal-point description (used for smart-crop)
    - rotation: "none" | "clockwise" | "counterclockwise"

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
    "subject" => nil,
    "rotation" => "none"
  }

  # Schema used for landscape images — no rotation field.
  @analysis_schema %{
    type: "OBJECT",
    properties: %{
      text_color: %{
        type: "STRING",
        enum: ["#FFFFFF", "#1A1A1A"],
        description:
          "Choose #FFFFFF (white) when the image is predominantly dark or high-contrast; choose #1A1A1A (near-black) when the image is predominantly light or pastel."
      },
      bg_color: %{
        type: "STRING",
        description:
          "A hex color code (#RRGGBB) sampled or derived from the image that works well as a semi-transparent text-overlay background. Should be a mid-tone or deep color from the image palette, not pure black or pure white."
      },
      bg_opacity: %{
        type: "NUMBER",
        description:
          "Opacity for the text overlay background box, between 0.60 (more transparent) and 0.85 (more opaque). Use lower values when the image background behind the overlay area is calm; higher values when it is busy or high-contrast."
      },
      subject: %{
        type: "STRING",
        description:
          "One sentence identifying the main subject or focal point. Used for smart-cropping: describe the object, region, or feature the eye is drawn to first (e.g. 'the bright spiral core of a galaxy', 'a close-up of a planetary nebula's central ring', 'an astronaut conducting a spacewalk against the dark of space')."
      }
    },
    required: ["text_color", "bg_color", "bg_opacity", "subject"]
  }

  # Schema used for portrait images — includes rotation.
  @combined_schema %{
    type: "OBJECT",
    properties: %{
      text_color: %{
        type: "STRING",
        enum: ["#FFFFFF", "#1A1A1A"],
        description:
          "Choose #FFFFFF (white) when the image is predominantly dark or high-contrast; choose #1A1A1A (near-black) when the image is predominantly light or pastel."
      },
      bg_color: %{
        type: "STRING",
        description:
          "A hex color code (#RRGGBB) sampled or derived from the image that works well as a semi-transparent text-overlay background. Should be a mid-tone or deep color from the image palette, not pure black or pure white."
      },
      bg_opacity: %{
        type: "NUMBER",
        description:
          "Opacity for the text overlay background box, between 0.60 (more transparent) and 0.85 (more opaque). Use lower values when the image background behind the overlay area is calm; higher values when it is busy or high-contrast."
      },
      subject: %{
        type: "STRING",
        description:
          "One sentence identifying the main subject or focal point. Used for smart-cropping: describe the object, region, or feature the eye is drawn to first (e.g. 'the bright spiral core of a galaxy', 'a close-up of a planetary nebula's central ring', 'an astronaut conducting a spacewalk against the dark of space')."
      },
      rotation: %{
        type: "STRING",
        enum: ["none", "clockwise", "counterclockwise"],
        description: """
        This is a portrait image that will be displayed in a 1920×1080 landscape format.
        Decide whether it was photographed/composed vertically because the subject genuinely
        requires a vertical orientation, or merely because of camera angle or page layout.

        none — ONLY when the subject has an inherent, meaningful vertical axis: a standing
               or upright person/animal, a rocket mid-launch, a tall tree or building, a
               waterfall, a cliff face, or a scene with a clear horizon line.
               Do NOT return "none" for printed plates, specimen sheets, or illustration
               pages — these are visual content, not documents; text labels, captions,
               plate numbers, and titles do not make an image "intentionally vertical".

        clockwise — the subject has no natural vertical requirement AND rotating 90° clockwise
                    makes it read naturally. Typically: the main mass or focal point is on the
                    LEFT side of the image. Use for biological close-ups, spread anatomical
                    details (wings, fins, claws, tentacles, roots), macro shots, scientific
                    illustration plates, overhead views, and galaxies/nebulae lying on their side.

        counterclockwise — same as clockwise but the main mass or focal point is on the RIGHT
                           side of the image.

        For symmetric images with no clear left/right bias (e.g. a centred plate with specimens
        arranged in a grid), default to "clockwise".

        Prefer rotation over "none" unless the subject is clearly and inherently vertical.
        """
      }
    },
    required: ["text_color", "bg_color", "bg_opacity", "subject", "rotation"]
  }

  @analysis_prompt """
  You are analyzing a scientific or astronomical image that will be displayed as a
  1920×1080 wallpaper with a text overlay (title + description) rendered in the
  lower-left corner.

  Return four values:

  text_color
    The best color for the overlay text. Must be exactly "#FFFFFF" (white) or
    "#1A1A1A" (near-black). Choose white for dark or high-contrast images (space
    scenes, nebulae, galaxies); choose near-black only for images with a
    predominantly light or pastel background.

  bg_color
    A hex color (#RRGGBB) to use as the semi-transparent background of the text
    overlay box. Pick a mid-tone or deep color sampled from the image's own
    palette — not pure black (#000000) and not pure white (#FFFFFF). Earthy,
    cosmic, or muted tones work well (e.g. deep navy, dusty violet, dark teal).

  bg_opacity
    A number between 0.60 and 0.85. Use ~0.65 when the area behind the overlay
    is calm and low-contrast; use ~0.80–0.85 when it is busy, bright, or
    high-contrast.

  subject
    One concise sentence naming the main focal point. This is used by the
    smart-crop algorithm to center the crop on the subject. Examples:
      "The bright, glowing core of the Whirlpool Galaxy and its spiral arms."
      "A close-up of the Pillars of Creation rising from the Eagle Nebula."
      "Two astronauts on a spacewalk against the curvature of Earth below."
  """

  @combined_prompt """
  You are analyzing a portrait-orientation scientific or astronomical image that
  will be displayed as a 1920×1080 landscape wallpaper with a text overlay
  (title + description) in the lower-left corner.

  Return five values:

  text_color
    The best color for the overlay text. Must be exactly "#FFFFFF" (white) or
    "#1A1A1A" (near-black). Choose white for dark or high-contrast images (space
    scenes, nebulae, galaxies); choose near-black only for images with a
    predominantly light or pastel background.

  bg_color
    A hex color (#RRGGBB) to use as the semi-transparent background of the text
    overlay box. Pick a mid-tone or deep color sampled from the image's own
    palette — not pure black (#000000) and not pure white (#FFFFFF).

  bg_opacity
    A number between 0.60 and 0.85. Use ~0.65 when the area behind the overlay
    is calm and low-contrast; use ~0.80–0.85 when it is busy, bright, or
    high-contrast.

  subject
    One concise sentence naming the main focal point used by the smart-crop
    algorithm. Examples:
      "The bright, glowing core of the Whirlpool Galaxy and its spiral arms."
      "A close-up of the Pillars of Creation rising from the Eagle Nebula."

  rotation
    The 90° rotation needed to produce the best 1920×1080 landscape display.

    Ask yourself: does this subject NEED to be tall to make sense in the real world?

    "none" — ONLY when the subject has a genuine, inherent vertical axis: a standing
    or upright person/animal, a rocket mid-launch, a tall tree or building, a waterfall,
    a cliff face, or a scene with a clear horizon line. Do NOT return "none" merely
    because the subject fills a portrait frame, and do NOT treat printed illustration
    plates, specimen sheets, or labelled scientific plates as "intentionally vertical" —
    text labels, captions, and plate titles are not a reason to keep portrait orientation.

    "clockwise" — the subject has no natural vertical requirement (e.g. a biological
    close-up, spread anatomical detail, macro shot, scientific illustration plate,
    overhead view, or galaxy/nebula lying on its side) AND rotating 90° clockwise makes
    it read naturally. Typically: the main mass or focal point is on the LEFT side.
    For symmetric images with no clear bias (e.g. a centred specimen plate), use clockwise.

    "counterclockwise" — same as clockwise but the main mass or focal point is on the
    RIGHT side of the image.

    Biological content, macro shots, illustration plates, and abstract structures almost
    always benefit from rotation. Prefer rotation unless the subject is clearly and
    inherently vertical.
  """

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Catalog.get_item!(item_id)
    Logger.info("[AnalyzeWorker] item=#{item_id}")

    with {:ok, original_binary} <- download_original(item),
         {:ok, img} <- Image.from_binary(original_binary),
         {:ok, {analysis, output_binary}} <- analyze_and_rotate(img, original_binary, item.manual_rotation),
         {:ok, item} <- persist(item, analysis, output_binary, original_binary) do
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

  # ---------------------------------------------------------------------------
  # Download
  # ---------------------------------------------------------------------------

  defp download_original(%{original_image: nil}), do: {:error, "item has no original_image"}

  defp download_original(item) do
    url = @uploader.url({item.original_image, item})
    Logger.debug("[AnalyzeWorker] fetching original url=#{url}")

    case @http.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "storage HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Combined analyze + rotate
  # ---------------------------------------------------------------------------

  # Returns {:ok, {analysis_map, output_binary}} where output_binary may be the
  # original (no rotation) or a freshly rotated binary.
  defp analyze_and_rotate(img, original_binary, manual_rotation) do
    width = Image.width(img)
    height = Image.height(img)
    portrait? = height > width

    Logger.debug("[AnalyzeWorker] dimensions #{width}×#{height}, portrait=#{portrait?}, manual_rotation=#{inspect(manual_rotation)}")

    with {:ok, preview} <- build_preview(img),
         {:ok, preview_binary} <- Image.write(preview, :memory, suffix: ".jpg", quality: 80) do
      if manual_rotation do
        # Manual override: use analysis-only Gemini call, apply the specified rotation.
        Logger.info("[AnalyzeWorker] using manual rotation: #{manual_rotation}")
        analyze_with_manual_rotation(img, original_binary, preview_binary, manual_rotation)
      else
        if portrait? do
          analyze_portrait(img, original_binary, preview_binary)
        else
          analyze_landscape(original_binary, preview_binary)
        end
      end
    end
  end

  defp build_preview(img) do
    Image.thumbnail(img, 800)
  end

  defp analyze_with_manual_rotation(img, original_binary, preview_binary, rotation) do
    analysis =
      case @gemini.generate_structured_with_image(@analysis_prompt, preview_binary, @analysis_schema, []) do
        {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _, "subject" => _} = result} ->
          Map.put(result, "rotation", rotation)

        _ ->
          Logger.warning("[AnalyzeWorker] Gemini analysis failed, using defaults")
          Map.put(@default_analysis, "rotation", rotation)
      end

    {analysis, output_binary} = apply_rotation(img, original_binary, analysis, rotation)
    {:ok, {analysis, output_binary}}
  end

  defp analyze_landscape(original_binary, preview_binary) do
    analysis =
      case @gemini.generate_structured_with_image(@analysis_prompt, preview_binary, @analysis_schema, []) do
        {:ok, %{"text_color" => _, "bg_color" => _, "bg_opacity" => _, "subject" => _} = result} ->
          Map.put(result, "rotation", "none")

        _ ->
          Logger.warning("[AnalyzeWorker] Gemini analysis failed, using defaults")
          @default_analysis
      end

    {:ok, {analysis, original_binary}}
  end

  defp analyze_portrait(img, original_binary, preview_binary) do
    {analysis, output_binary} =
      case @gemini.generate_structured_with_image(@combined_prompt, preview_binary, @combined_schema, []) do
        {:ok,
         %{
           "text_color" => _,
           "bg_color" => _,
           "bg_opacity" => _,
           "subject" => _,
           "rotation" => rotation
         } = result}
        when rotation in ["none", "clockwise", "counterclockwise"] ->
          Logger.info("[AnalyzeWorker] Gemini rotation decision: #{rotation}")
          apply_rotation(img, original_binary, result, rotation)

        _ ->
          Logger.warning("[AnalyzeWorker] Gemini combined call failed, using defaults")
          {@default_analysis, original_binary}
      end

    {:ok, {analysis, output_binary}}
  end

  defp apply_rotation(_img, original_binary, analysis, "none"), do: {analysis, original_binary}

  defp apply_rotation(img, original_binary, analysis, direction) do
    degrees = if direction == "clockwise", do: 90, else: -90

    case Image.rotate(img, degrees) do
      {:ok, rotated} ->
        case Image.write(rotated, :memory, suffix: ".jpg", quality: 95) do
          {:ok, rotated_binary} -> {analysis, rotated_binary}
          _ -> {analysis, original_binary}
        end

      _ ->
        {analysis, original_binary}
    end
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  defp persist(item, analysis, output_binary, original_binary) do
    params =
      if output_binary != original_binary do
        case @uploader.store({%{filename: "original.jpg", binary: output_binary}, item}) do
          {:ok, file} ->
            %{image_analysis: analysis, original_image: %{file_name: file, updated_at: nil}}

          {:error, reason} ->
            Logger.warning("[AnalyzeWorker] rotation upload failed, keeping original: #{inspect(reason)}")
            %{image_analysis: analysis}
        end
      else
        %{image_analysis: analysis}
      end

    fsm_transition(item, "resize", params)
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

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
