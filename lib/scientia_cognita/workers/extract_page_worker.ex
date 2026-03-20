defmodule ScientiaCognita.Workers.ExtractPageWorker do
  @moduledoc """
  Fetches one page URL, extracts gallery items using stored CSS selectors (via Floki),
  persists items, enqueues download workers, and either loops to the next page
  or marks the source as done.

  Args: %{source_id: integer, url: string}
  """

  use Oban.Worker,
    queue: :fetch,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias ScientiaCognita.{Catalog, SourceFSM}
  alias ScientiaCognita.Workers.DownloadImageWorker

  @http Application.compile_env(:scientia_cognita, :http_module, ScientiaCognita.Http)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "url" => url}}) do
    source = Catalog.get_source!(source_id)
    Logger.info("[ExtractPageWorker] source=#{source_id} url=#{url}")

    with {:ok, html} <- fetch(url),
         {:ok, tree} <- Floki.parse_document(html),
         items = extract_items(tree, source),
         next_url = extract_next_url(tree, source),
         {:ok, db_items} <- create_items(items, source_id),
         :ok <- enqueue_downloads(db_items) do
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
      {:error, reason} ->
        Logger.error("[ExtractPageWorker] failed source=#{source_id}: #{inspect(reason)}")
        source = Catalog.get_source!(source_id)
        {:ok, failed} = Catalog.update_source_status(source, "failed", error: inspect(reason))
        broadcast(source_id, {:source_updated, failed})
        :ok
    end
  end

  # ---------------------------------------------------------------------------

  defp fetch(url) do
    case @http.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_items(tree, source) do
    images = tree |> Floki.find(source.selector_image || "") |> Enum.map(&src_from_element/1)
    titles = tree |> Floki.find(source.selector_title || "") |> Enum.map(&Floki.text/1)
    descs  = list_or_empty(tree, source.selector_description)
    copies = list_or_empty(tree, source.selector_copyright)

    count = length(images)

    0..(max(count - 1, -1))
    |> Enum.map(fn i ->
      %{
        title: Enum.at(titles, i, "Untitled"),
        image_url: Enum.at(images, i),
        description: Enum.at(descs, i),
        copyright: Enum.at(copies, i)
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.image_url) end)
  end

  defp extract_next_url(_tree, %{selector_next_page: nil}), do: nil

  defp extract_next_url(tree, source) do
    case Floki.find(tree, source.selector_next_page) do
      [el | _] -> el |> Floki.attribute("href") |> List.first()
      [] -> nil
    end
  end

  defp list_or_empty(_tree, nil), do: []

  defp list_or_empty(tree, selector) do
    tree |> Floki.find(selector) |> Enum.map(&Floki.text/1)
  end

  defp src_from_element(el) do
    case Floki.attribute(el, "src") do
      [src | _] when src != "" -> src
      _ ->
        case Floki.attribute(el, "data-src") do
          [src | _] -> src
          _ -> nil
        end
    end
  end

  defp create_items(raw_items, source_id) do
    results =
      Enum.map(raw_items, fn item ->
        attrs = %{
          title: item.title,
          description: item.description,
          copyright: item.copyright,
          original_url: item.image_url,
          source_id: source_id,
          status: "pending"
        }

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
