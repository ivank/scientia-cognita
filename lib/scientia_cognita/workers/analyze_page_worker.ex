defmodule ScientiaCognita.Workers.AnalyzePageWorker do
  @moduledoc """
  Strips the stored raw_html, sends it to Gemini to:
  1. Classify whether the page is a scientific image gallery.
  2. Extract gallery title and description.
  3. Generate CSS selectors for extracting items on all pages.

  On success, stores selectors on the source and enqueues ExtractPageWorker.

  Args: %{source_id: integer}
  """

  use Oban.Worker, queue: :fetch, max_attempts: 3

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, SourceFSM}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @analyze_schema %{
    type: "OBJECT",
    properties: %{
      is_gallery: %{type: "BOOLEAN"},
      title: %{type: "STRING", nullable: true},
      description: %{type: "STRING", nullable: true},
      selector_title: %{type: "STRING", nullable: true},
      selector_image: %{type: "STRING", nullable: true},
      selector_description: %{type: "STRING", nullable: true},
      selector_copyright: %{type: "STRING", nullable: true},
      selector_next_page: %{type: "STRING", nullable: true}
    },
    required: ["is_gallery"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[AnalyzePageWorker] source=#{source_id}")

    clean_html = HTMLStripper.strip(source.raw_html || "")

    with {:ok, result} <- call_gemini(clean_html, source.url),
         :ok <- check_is_gallery(result, source_id),
         {:ok, "extracting"} <- SourceFSM.transition(source, :analyzed),
         {:ok, source} <- Catalog.update_source_analysis(source, build_analysis(result)),
         {:ok, source} <- Catalog.update_source_status(source, "extracting") do
      broadcast(source_id, {:source_updated, source})
      %{source_id: source_id, url: source.url} |> ExtractPageWorker.new() |> Oban.insert()
      :ok
    else
      {:not_gallery} ->
        Logger.warning("[AnalyzePageWorker] source=#{source_id} is not a scientific image gallery")
        source = Catalog.get_source!(source_id)
        {:ok, "failed"} = SourceFSM.transition(source, :not_gallery)
        {:ok, failed} = Catalog.update_source_status(source, "failed",
          error: "Page is not a scientific image gallery. Check the source URL and try again.")
        broadcast(source_id, {:source_updated, failed})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[AnalyzePageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[AnalyzePageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        :ok
    end
  end

  defp call_gemini(clean_html, base_url) do
    prompt = """
    Analyze the following HTML page and determine whether it is a scientific image gallery.

    A scientific image gallery is a page whose PRIMARY purpose is to display a curated
    collection of scientific, nature, or educational images — for example: astronomy
    photos, microscopy images, wildlife photography, geological surveys, medical imaging,
    museum collections, or science journalism photo essays.

    Set is_gallery to FALSE if the page is primarily: a news article, a product page,
    a blog post, a social media feed, a search results page, or any page where images
    are incidental rather than the main content.

    If is_gallery is TRUE:
    - Extract the gallery title and description.
    - Provide CSS selectors to extract these fields for EACH gallery item:
      * selector_title: selects the title/caption element for each item
      * selector_image: selects the <img> element for each item
      * selector_description: selects the description/caption element (or null)
      * selector_copyright: selects the copyright/credit element (or null)
      * selector_next_page: selects the <a> link to the next page (or null if none)

    The selectors must work with Floki (CSS selector syntax).
    Base URL for resolving relative paths: #{base_url}

    HTML:
    #{clean_html}
    """

    @gemini.generate_structured(prompt, @analyze_schema, [])
  end

  defp check_is_gallery(%{"is_gallery" => false}, _source_id), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}, _source_id), do: :ok
  defp check_is_gallery(_, _source_id), do: {:not_gallery}

  defp build_analysis(result) do
    %{
      gallery_title: result["title"],
      gallery_description: result["description"],
      selector_title: result["selector_title"],
      selector_image: result["selector_image"],
      selector_description: result["selector_description"],
      selector_copyright: result["selector_copyright"],
      selector_next_page: result["selector_next_page"]
    }
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
