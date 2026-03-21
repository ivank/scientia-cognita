defmodule ScientiaCognitaWeb.Console.SourcesLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Catalog.Source
  alias ScientiaCognita.Workers.FetchPageWorker

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Sources</h1>
          <p class="text-base-content/60 mt-1">Content sources to crawl and extract items from</p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="open_new_modal">
          <.icon name="hero-plus" class="size-4" /> Add Source
        </button>
      </div>

      <div :if={@sources == []} class="card bg-base-200 p-12 text-center">
        <.icon name="hero-globe-alt" class="size-12 mx-auto text-base-content/30" />
        <p class="mt-3 text-base-content/50">No sources yet. Add one to get started.</p>
      </div>

      <div class="grid gap-4">
        <.link
          :for={source <- @sources}
          navigate={~p"/console/sources/#{source.id}"}
          class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
        >
          <div class="card-body py-4">
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="font-semibold">{source.name}</span>
                  <.status_badge status={source.status} />
                </div>
                <p class="text-sm text-base-content/50 truncate mt-0.5">{source.url}</p>
              </div>
              <div class="flex gap-6 text-sm text-right shrink-0">
                <div>
                  <div class="font-semibold">{source.total_items}</div>
                  <div class="text-base-content/50 text-xs">items</div>
                </div>
                <div>
                  <div class="font-semibold">{source.pages_fetched}</div>
                  <div class="text-base-content/50 text-xs">pages</div>
                </div>
              </div>
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
        <h3 class="font-bold text-lg">Add Source</h3>
        <p class="text-sm text-base-content/60 mt-1 mb-5">
          Enter a URL to begin crawling. Gemini will extract items page by page.
        </p>

        <.form for={@form} phx-submit="create_source" phx-change="validate_source">
          <div class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <.input field={@form[:name]} placeholder="e.g. Unsplash Nature Photos" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Starting URL</span></label>
              <.input field={@form[:url]} type="url" placeholder="https://..." />
            </div>
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
            <button type="submit" class="btn btn-primary" phx-disable-with="Creating…">
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
    {:ok,
     socket
     |> assign(:sources, Catalog.list_sources())
     |> assign(:show_new_modal, false)
     |> assign(:form, to_form(Catalog.change_source(%Source{})))}
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
        %{source_id: source.id}
        |> FetchPageWorker.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> assign(:sources, Catalog.list_sources())
         |> assign(:show_new_modal, false)
         |> assign(:form, to_form(Catalog.change_source(%Source{})))
         |> put_flash(:info, "Source created — crawling started")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp status_badge(assigns) do
    ~H"""
    <span class={"badge badge-sm #{status_class(@status)}"}>{@status}</span>
    """
  end

  defp status_class("pending"), do: "badge-ghost"
  defp status_class("fetching"), do: "badge-warning animate-pulse"
  defp status_class("extracting"), do: "badge-warning animate-pulse"
  defp status_class("done"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class(_), do: "badge-ghost"
end
