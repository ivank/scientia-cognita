defmodule ScientiaCognita.Workers.CrawlPageWorker do
  @moduledoc """
  Fetches a single page URL, strips the HTML, asks Gemini to extract items,
  creates Item records, enqueues image workers, and follows pagination.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, Gemini, HTMLStripper}
  alias ScientiaCognita.Workers.DownloadImageWorker

  # Structured output schema — Gemini will always return exactly this shape.
  @extraction_schema %{
    type: "OBJECT",
    properties: %{
      is_gallery: %{
        type: "BOOLEAN"
      },
      items: %{
        type: "ARRAY",
        items: %{
          type: "OBJECT",
          properties: %{
            title: %{type: "STRING"},
            description: %{type: "STRING", nullable: true},
            image_url: %{type: "STRING"},
            author: %{type: "STRING", nullable: true},
            copyright: %{type: "STRING", nullable: true}
          },
          required: ["title", "image_url"]
        }
      },
      next_page_url: %{type: "STRING", nullable: true}
    },
    required: ["is_gallery", "items", "next_page_url"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "url" => url}}) do
    source = Catalog.get_source!(source_id)

    # Mark running on first page
    if source.pages_fetched == 0 do
      {:ok, _} = Catalog.update_source_status(source, "running")
    end

    Logger.info("[CrawlPageWorker] source=#{source_id} url=#{url}")

    with {:ok, html} <- fetch_page(url),
         clean_html = HTMLStripper.strip(html),
         {:ok, %{"is_gallery" => true, "items" => raw_items, "next_page_url" => next_url}} <-
           extract_with_gemini(clean_html, url),
         {:ok, items} <- create_items(raw_items, source_id),
         :ok <- enqueue_image_workers(items) do
      source = Catalog.get_source!(source_id)

      progress = %{
        pages_fetched: source.pages_fetched + 1,
        total_items: source.total_items + length(items),
        next_page_url: next_url
      }

      {:ok, source} = Catalog.update_source_progress(source, progress)

      broadcast(source_id, {:source_updated, source})

      if next_url && next_url != url do
        %{source_id: source_id, url: next_url}
        |> __MODULE__.new()
        |> Oban.insert()
      else
        {:ok, done} = Catalog.update_source_status(source, "done")
        broadcast(source_id, {:source_updated, done})
      end

      :ok
    else
      {:ok, %{"is_gallery" => false}} ->
        Logger.warning("[CrawlPageWorker] source=#{source_id} url=#{url} is not a scientific image gallery — aborting crawl")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed",
          error: "Page is not a scientific image gallery. Check the source URL and try again.")
        broadcast(source_id, {:source_updated, failed})
        # Return :ok so Oban does not retry — this is a permanent abort, not a transient error.
        :ok

      {:error, reason} ->
        Logger.error("[CrawlPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_page(url) do
    case Req.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_with_gemini(html, base_url) do
    prompt = """
    Analyze the following HTML page and determine whether it is a scientific image gallery.

    A scientific image gallery is a page whose PRIMARY purpose is to display a curated
    collection of scientific, nature, or educational images — for example: astronomy
    photos, microscopy images, wildlife photography, geological surveys, medical imaging,
    museum collections, or science journalism photo essays.

    Set is_gallery to FALSE if the page is primarily: a news article, a product page,
    a blog post, a social media feed, a search results page, or any page where images
    are incidental rather than the main content.

    If is_gallery is TRUE, extract only the gallery images — not navigation icons,
    logos, ads, thumbnails for unrelated articles, or UI elements.

    For each gallery image include:
    - title: the image's title or caption heading
    - description: a short description or caption body (1–3 sentences), or null
    - image_url: absolute URL to the full-size image — convert relative paths using base URL: #{base_url}
    - author: photographer or creator name, or null
    - copyright: copyright notice, or null

    Also provide next_page_url: the absolute URL to the next page of the gallery, or null.

    If is_gallery is FALSE, return an empty items array and null for next_page_url.

    HTML:
    #{html}
    """

    case Gemini.generate_structured(prompt, @extraction_schema) do
      {:ok, %{"is_gallery" => _, "items" => _, "next_page_url" => _} = result} ->
        {:ok, result}

      {:ok, other} ->
        Logger.warning("[CrawlPageWorker] Unexpected Gemini response: #{inspect(other)}")
        {:ok, %{"is_gallery" => false, "items" => [], "next_page_url" => nil}}

      {:error, reason} ->
        {:error, "Gemini extraction failed: #{inspect(reason)}"}
    end
  end

  defp create_items(raw_items, source_id) do
    results =
      Enum.map(raw_items, fn item ->
        attrs = %{
          title: Map.get(item, "title") || "Untitled",
          description: Map.get(item, "description"),
          author: Map.get(item, "author"),
          copyright: Map.get(item, "copyright"),
          original_url: Map.get(item, "image_url"),
          source_id: source_id,
          status: "pending"
        }

        case Catalog.create_item(attrs) do
          {:ok, item} -> item
          {:error, changeset} ->
            Logger.warning("[CrawlPageWorker] item insert failed: #{inspect(changeset.errors)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  end

  defp enqueue_image_workers(items) do
    Enum.each(items, fn item ->
      if item.original_url do
        %{item_id: item.id}
        |> DownloadImageWorker.new()
        |> Oban.insert()
      end
    end)

    :ok
  end

  defp broadcast(source_id, event) do
    Phoenix.PubSub.broadcast(
      ScientiaCognita.PubSub,
      "source:#{source_id}",
      event
    )
  end
end
