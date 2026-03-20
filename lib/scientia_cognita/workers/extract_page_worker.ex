defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  Fetches one page URL, strips HTML, calls Gemini to extract gallery items
  directly (image_url, title, description, copyright), persists items,
  enqueues download workers, and either loops to the next page or marks
  the source as done.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, SourceFSM}
  alias ScientiaCognita.Workers.DownloadImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @extract_schema %{
    type: "OBJECT",
    properties: %{
      is_gallery: %{type: "BOOLEAN"},
      gallery_title: %{type: "STRING", nullable: true},
      gallery_description: %{type: "STRING", nullable: true},
      next_page_url: %{type: "STRING", nullable: true},
      items: %{
        type: "ARRAY",
        items: %{
          type: "OBJECT",
          properties: %{
            image_url: %{type: "STRING", nullable: true},
            title: %{type: "STRING", nullable: true},
            description: %{type: "STRING", nullable: true},
            copyright: %{type: "STRING", nullable: true}
          },
          required: ["image_url"]
        }
      }
    },
    required: ["is_gallery", "items"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "url" => url}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[ExtractPageWorker] source=#{source_id} url=#{url}")

    with {:ok, html} <- fetch(url),
         clean_html = HTMLStripper.strip(html),
         {:ok, result} <- call_gemini(clean_html, url),
         :ok <- check_is_gallery(result, source_id, source),
         {:ok, source} <- store_gallery_info(result, source),
         items = build_items(result["items"] || [], source_id),
         {:ok, db_items} <- create_items(items),
         :ok <- enqueue_downloads(db_items) do

      next_url = result["next_page_url"]
      progress = %{
        pages_fetched: source.pages_fetched + 1,
        total_items: source.total_items + length(db_items),
        next_page_url: next_url
      }

      {:ok, source} = Catalog.update_source_progress(source, progress)
      broadcast(source_id, {:source_updated, source})

      if next_url && next_url != url do
        {:ok, "extracting"} = SourceFSM.transition(source, :page_done)
        %{source_id: source_id, url: next_url} |> __MODULE__.new() |> Oban.insert()
      else
        {:ok, "done"} = SourceFSM.transition(source, :exhausted)
        {:ok, done} = Catalog.update_source_status(source, "done")
        broadcast(source_id, {:source_updated, done})
      end

      :ok
    else
      {:not_gallery} ->
        Logger.warning("[ExtractPageWorker] source=#{source_id} is not a scientific image gallery")
        source = Catalog.get_source!(source_id)
        {:ok, "failed"} = SourceFSM.transition(source, :not_gallery)
        {:ok, failed} = Catalog.update_source_status(source, "failed",
          error: "Page is not a scientific image gallery. Check the source URL and try again.")
        broadcast(source_id, {:source_updated, failed})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[ExtractPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        :ok
    end
  end

  @doc "Returns the Gemini structured-output schema for item extraction."
  def extract_schema, do: @extract_schema

  @doc "Builds the Gemini prompt for extracting gallery items from a page."
  def build_extract_prompt(clean_html, base_url) do
    """
    Analyze the following HTML page and extract scientific image gallery data.

    Determine if this page is a scientific image gallery (astronomy, microscopy,
    wildlife photography, geological surveys, medical imaging, museum collections,
    or science journalism photo essays). Set is_gallery to false for news articles,
    product pages, blog posts, or pages where images are incidental.

    If is_gallery is true:
    - Set gallery_title and gallery_description from the page content.
    - Find ALL gallery items and for each extract:
      * image_url (REQUIRED): The image URL. If a srcset attribute is present,
        return the URL with the largest width descriptor (e.g. prefer "1600w" over "400w").
        Otherwise use the src attribute. Always return absolute URLs.
      * title: The image heading or title (null if absent).
      * description: A description or caption, summarized to under 300 characters (null if absent).
      * copyright: The copyright or credit line (null if absent).
    - Set next_page_url to the absolute URL of the "next page" link if pagination
      exists (null if this is a single page or the last page).

    Base URL for resolving relative URLs: #{base_url}

    HTML:
    #{clean_html}
    """
  end

  # ---------------------------------------------------------------------------

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_gemini(clean_html, base_url) do
    @gemini.generate_structured(build_extract_prompt(clean_html, base_url), @extract_schema, [])
  end

  defp check_is_gallery(%{"is_gallery" => false}, _source_id, _source), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}, _source_id, _source), do: :ok
  defp check_is_gallery(_, _source_id, _source), do: {:not_gallery}

  defp store_gallery_info(result, source) do
    Catalog.update_source_analysis(source, %{
      gallery_title: result["gallery_title"],
      gallery_description: result["gallery_description"]
    })
  end

  defp build_items(raw_items, source_id) do
    raw_items
    |> Enum.map(fn item ->
      %{
        title: item["title"] || "Untitled",
        description: item["description"],
        copyright: item["copyright"],
        original_url: item["image_url"],
        source_id: source_id,
        status: "pending"
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.original_url) end)
  end

  defp create_items(items) do
    results =
      Enum.map(items, fn attrs ->
        case Catalog.create_item(attrs) do
          {:ok, item} -> item
          {:error, cs} ->
            Logger.warning("[ExtractPageWorker] item insert failed: #{inspect(cs.errors)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  end

  defp enqueue_downloads(items) do
    Enum.each(items, fn item ->
      if item.original_url do
        %{item_id: item.id} |> DownloadImageWorker.new() |> Oban.insert()
      end
    end)

    :ok
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(ScientiaCognita.PubSub, "source:#{source_id}", event)
  end
end
