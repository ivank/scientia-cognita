defmodule ScientiaCognitaWeb.Console.SourcesLive do
  use ScientiaCognitaWeb, :live_view

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Catalog.Source
  alias ScientiaCognita.Uploaders.ItemImageUploader
  alias ScientiaCognita.Workers.FetchPageWorker

  @preview_cap 6

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.breadcrumb items={[
        %{label: "Console", href: ~p"/console"},
        %{label: "Sources"}
      ]} />
      <div class="flex items-center justify-between">
        <div>
          <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
            Sources
          </h1>
          <p class="text-neutral text-sm mt-1">
            URLs crawled and extracted by Gemini into individual items
          </p>
        </div>
        <button class="btn btn-primary btn-sm gap-2" phx-click="open_new_modal">
          <.icon name="hero-plus" class="size-4" /> Add Source
        </button>
      </div>

      <%!-- Empty state --%>
      <div :if={@sources == []} class="card bg-base-200 p-16 text-center">
        <.icon name="hero-globe-alt" class="size-12 mx-auto text-base-content/20" />
        <p class="mt-4 text-base-content/50 text-sm">No sources yet. Add a URL to begin.</p>
      </div>

      <%!-- Source list --%>
      <div class="grid gap-2">
        <.link
          :for={source <- @sources}
          navigate={~p"/console/sources/#{source.id}"}
          class="card bg-base-200 hover:bg-base-300 transition-colors duration-150 cursor-pointer overflow-hidden"
        >
          <div class="card-body py-4 px-5 gap-3">
            <%!-- Source info row --%>
            <div class="flex items-start gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="font-semibold text-sm">{Source.display_name(source)}</span>
                  <.status_badge status={source.status} />
                </div>
                <p class="text-xs text-base-content/40 truncate mt-0.5 font-mono">{source.url}</p>
              </div>
              <div class="flex gap-5 text-right shrink-0 text-sm">
                <div>
                  <div class="font-semibold">{source.total_items}</div>
                  <div class="text-base-content/40 text-xs">items</div>
                </div>
                <div>
                  <div class="font-semibold">{source.pages_fetched}</div>
                  <div class="text-base-content/40 text-xs">pages</div>
                </div>
              </div>
            </div>

            <%!-- Thumbnail strip --%>
            <div class="flex gap-1.5" style="height: 48px;">
              <div
                :for={item <- source.items}
                class="shrink-0 rounded overflow-hidden bg-base-300"
                style="width: 76px; height: 48px;"
              >
                <img
                  :if={item.thumbnail_image || item.final_image}
                  src={
                    if item.thumbnail_image,
                      do: ItemImageUploader.url({item.thumbnail_image, item}),
                      else: ItemImageUploader.url({item.final_image, item})
                  }
                  class="w-full h-full object-cover"
                  loading="lazy"
                />
              </div>
              <%!-- Shimmer placeholders for in-flight items --%>
              <div
                :for={_ <- shimmer_placeholders(source)}
                class="skeleton shrink-0 rounded"
                style="width: 76px; height: 48px;"
              />
            </div>
          </div>
        </.link>
      </div>
    </div>

    <%!-- New Source modal --%>
    <div
      :if={@show_new_modal}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_modal"
    >
      <div class="modal-box">
        <h3 style="font-family: var(--sc-font-serif);" class="text-lg text-base-content">Add Source</h3>
        <p class="text-sm text-base-content/60 mt-1 mb-5">
          Enter the starting URL. Gemini will extract the title, items, and pagination automatically.
        </p>

        <.form for={@form} phx-submit="create_source" phx-change="validate_source">
          <div class="form-control">
            <label class="label pb-1">
              <span class="label-text text-xs uppercase tracking-wide font-medium">Starting URL</span>
            </label>
            <.input field={@form[:url]} type="url" placeholder="https://…" />
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost btn-sm" phx-click="close_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Creating…">
              Start Crawling
            </button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    sources = Catalog.list_sources_with_preview()

    if connected?(socket) do
      Enum.each(sources, fn source ->
        Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "source:#{source.id}")
      end)
    end

    {:ok,
     socket
     |> assign(:nav_section, :sources)
     |> assign(:sources, sources)
     |> assign(:show_new_modal, false)
     |> assign(:form, to_form(Catalog.change_source(%Source{})))}
  end

  @impl true
  def handle_info({:source_updated, updated_source}, socket) do
    source = Catalog.get_source_with_preview(updated_source.id)
    {:noreply, assign(socket, :sources, replace_source(socket.assigns.sources, source))}
  end

  def handle_info({:item_updated, item}, socket) do
    source = Catalog.get_source_with_preview(item.source_id)
    {:noreply, assign(socket, :sources, replace_source(socket.assigns.sources, source))}
  end

  @impl true
  def handle_event("open_new_modal", _, socket) do
    {:noreply, assign(socket, show_new_modal: true)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, show_new_modal: false)}
  end

  def handle_event("validate_source", %{"source" => params}, socket) do
    form =
      %Source{}
      |> Catalog.change_source(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create_source", %{"source" => params}, socket) do
    case Catalog.create_source(params) do
      {:ok, source} ->
        Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "source:#{source.id}")

        %{source_id: source.id}
        |> FetchPageWorker.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> assign(:sources, Catalog.list_sources_with_preview())
         |> assign(:show_new_modal, false)
         |> assign(:form, to_form(Catalog.change_source(%Source{})))
         |> put_flash(:info, "Source created — crawling started")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp replace_source(sources, updated) do
    Enum.map(sources, fn s -> if s.id == updated.id, do: updated, else: s end)
  end

  defp shimmer_placeholders(source) do
    ready_count = length(source.items)

    count =
      cond do
        source.status in ~w(pending fetching extracting items_loading) and
            source.total_items == 0 ->
          max(0, @preview_cap - ready_count)

        source.total_items > ready_count ->
          min(source.total_items - ready_count, @preview_cap - ready_count)

        true ->
          0
      end

    List.duplicate(nil, max(count, 0))
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={"badge badge-sm #{status_class(@status)}"}>{@status}</span>
    """
  end

  defp status_class("pending"), do: "badge-ghost"
  defp status_class("fetching"), do: "badge-warning animate-pulse"
  defp status_class("extracting"), do: "badge-warning animate-pulse"
  defp status_class("items_loading"), do: "badge-info animate-pulse"
  defp status_class("done"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class(_), do: "badge-ghost"
end
