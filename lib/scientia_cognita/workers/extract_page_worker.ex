defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  For each page URL: strips HTML, calls Gemini to extract gallery items,
  appends a GeminiPageResult to the source, persists items, enqueues
  DownloadImageWorkers, and either loops to the next page (extracting → extracting)
  or transitions to items_loading.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, HTMLStripper, Repo}
  alias ScientiaCognita.Catalog.GeminiPageResult
  alias ScientiaCognita.Workers.DownloadImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)
  @gemini Application.compile_env(:scientia_cognita, :gemini_module, ScientiaCognita.Gemini)

  @extract_schema %{
    type: "OBJECT",
    description:
      "Structured extraction of a scientific image gallery page. " <>
        "Extract every gallery item present — including hidden, off-screen, aria-hidden, " <>
        "lazy-loaded items, and items inside carousels, sliders, or slideshow containers. " <>
        "Do not stop at the first few visible items.",
    properties: %{
      is_gallery: %{
        type: "BOOLEAN",
        description:
          "True if this page is a scientific image gallery — astronomy, microscopy, " <>
            "wildlife photography, geological surveys, medical imaging, museum collections, " <>
            "or science journalism photo essays. False for news articles, product pages, " <>
            "blog posts, or pages where images are merely decorative."
      },
      gallery_title: %{
        type: "STRING",
        nullable: true,
        description: "Title of the gallery, from page headings or metadata. Null if absent."
      },
      gallery_description: %{
        type: "STRING",
        nullable: true,
        description: "Brief description of the gallery from page content. Null if absent."
      },
      gallery_copyright: %{
        type: "STRING",
        nullable: true,
        description:
          "Generic copyright or credit line that applies to the entire gallery — " <>
            "e.g. '© NASA', 'ESA/Hubble', 'Image credit: NOAA'. " <>
            "Look for a site-wide footer credit, a masthead attribution, or a repeated " <>
            "credit that appears on every image. Null if no gallery-level copyright is present."
      },
      next_page_url: %{
        type: "STRING",
        nullable: true,
        description:
          "Absolute URL of the next-page link if pagination exists. " <>
            "Resolve relative URLs using the base URL. Null on single-page or last page."
      },
      items: %{
        type: "ARRAY",
        description:
          "Every gallery item in the HTML. Include items that are currently hidden or " <>
            "off-screen (aria-hidden, display:none), not yet loaded (lazy-loaded images), " <>
            "inside carousels or sliders regardless of slide position, and every numbered " <>
            "section in compilation or roundup articles.",
        items: %{
          type: "OBJECT",
          properties: %{
            image_url: %{
              type: "STRING",
              description:
                "Absolute image URL. Check in this priority order: " <>
                  "(1) srcset or data-srcset — pick the URL with the largest width descriptor (e.g. prefer 1600w over 400w); " <>
                  "(2) src — if it has no size/quality suffix (e.g. no -1200-80 pattern), prefer it as the original full-resolution URL; " <>
                  "(3) data-src, data-lazy-src, data-original, data-hi-res-src, data-full-src. " <>
                  "Always resolve relative URLs to absolute using the page base URL."
            },
            title: %{
              type: "STRING",
              nullable: true,
              description: "Image heading or caption title. Null if absent."
            },
            # Non-nullable + required: forces Gemini to pull text from alt,
            # figcaption, sibling content divs, or surrounding paragraphs
            # rather than defaulting to null.
            description: %{
              type: "STRING",
              description:
                "Description text for the image. Check in this priority order: " <>
                  "(1) The alt attribute on the img tag — many sites encode the full caption here; use it verbatim if longer than ~20 characters. " <>
                  "(2) A figcaption element that is NOT just a copyright or credit line. " <>
                  "(3) The first p element immediately following the closing figure tag — article and listicle galleries commonly place descriptions there. " <>
                  "(4) Any other nearby text clearly associated with the image. " <>
                  "Summarize to under 300 characters. Use empty string only if truly nothing is present."
            },
            copyright: %{
              type: "STRING",
              nullable: true,
              description:
                "Copyright or credit line — often inside a figcaption or a span " <>
                  "containing 'credit', 'copyright', or 'Image credit'. Null if absent."
            }
          },
          required: ["image_url", "description"]
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
         :ok <- check_is_gallery(result),
         gemini_page = build_gemini_page(result, url),
         items = build_items(result["items"] || [], source_id, result["gallery_copyright"]),
         {:ok, db_items} <- create_items(items) do
      next_url = result["next_page_url"]
      paginating = next_url && next_url != url
      new_state = if paginating, do: "extracting", else: "items_loading"

      transition_params =
        %{
          pages_fetched: source.pages_fetched + 1,
          total_items: source.total_items + length(db_items),
          next_page_url: next_url,
          gemini_page: gemini_page
        }
        |> then(fn p ->
          if new_state == "items_loading" do
            Map.merge(p, %{
              title: result["gallery_title"],
              description: result["gallery_description"],
              copyright: result["gallery_copyright"]
            })
          else
            p
          end
        end)

      {:ok, source} = fsm_transition(source, new_state, transition_params)
      :ok = enqueue_downloads(db_items)
      broadcast(source_id, {:source_updated, source})

      if paginating do
        %{source_id: source_id, url: next_url} |> __MODULE__.new() |> Oban.insert()
      end

      :ok
    else
      {:not_gallery} ->
        Logger.warning(
          "[ExtractPageWorker] source=#{source_id} is not a scientific image gallery"
        )

        source = Catalog.get_source!(source_id)

        {:ok, _} =
          fsm_transition(source, "failed", %{
            error: "Page is not a scientific image gallery. Check the source URL and try again."
          })

        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok

      {:error, :invalid_transition} ->
        Logger.warning("[ExtractPageWorker] invalid transition for source=#{source_id}")
        :ok

      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, _} = fsm_transition(source, "failed", %{error: inspect(reason)})
        broadcast(source_id, {:source_updated, Catalog.get_source!(source_id)})
        :ok
    end
  end

  @doc "Returns the Gemini structured-output schema for item extraction."
  def extract_schema, do: @extract_schema

  @doc "Builds the Gemini prompt for extracting gallery items from a page."
  def build_extract_prompt(clean_html, base_url) do
    """
    Extract scientific image gallery data from the HTML below.

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

  defp check_is_gallery(%{"is_gallery" => false}), do: {:not_gallery}
  defp check_is_gallery(%{"is_gallery" => true}), do: :ok
  defp check_is_gallery(_), do: {:not_gallery}

  defp build_gemini_page(result, url) do
    GeminiPageResult.new(%{
      page_url: url,
      is_gallery: result["is_gallery"],
      gallery_title: result["gallery_title"],
      gallery_description: result["gallery_description"],
      gallery_copyright: result["gallery_copyright"],
      next_page_url: result["next_page_url"],
      raw_items: result["items"] || []
    })
  end

  defp build_items(raw_items, source_id, gallery_copyright) do
    raw_items
    |> Enum.map(fn item ->
      %{
        title: item["title"] || "Untitled",
        description: item["description"],
        copyright: item["copyright"] || gallery_copyright,
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
          {:ok, item} ->
            item

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
