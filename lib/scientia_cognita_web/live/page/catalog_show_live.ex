defmodule ScientiaCognitaWeb.Page.CatalogShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :mount_current_scope}

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Storage

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8 space-y-6">
      <%!-- Header --%>
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <div class="flex items-center gap-2 text-sm text-base-content/50 mb-1">
            <.link navigate={~p"/"} class="hover:text-base-content">Catalogs</.link>
            <.icon name="hero-chevron-right" class="size-3" />
            <span>{@catalog.name}</span>
          </div>
          <h1 class="text-3xl font-bold">{@catalog.name}</h1>
          <p :if={@catalog.description} class="text-base-content/60 mt-1">{@catalog.description}</p>
        </div>

        <%!-- Save to Google Photos --%>
        <div>
          <%= cond do %>
            <% @export_job_id != nil -> %>
              <div class="flex flex-col items-end gap-1">
                <button class="btn btn-success btn-sm gap-2" disabled>
                  <span class="loading loading-spinner loading-xs"></span> Saving to Google Photos…
                </button>
                <span class="text-xs text-base-content/50">
                  {@export_progress} of {@export_total} uploaded
                </span>
              </div>
            <% @export_done -> %>
              <div class="flex flex-col items-end gap-1">
                <button class="btn btn-success btn-sm gap-2" disabled>
                  <.icon name="hero-check" class="size-4" /> Saved to Google Photos
                </button>
                <a
                  :if={@export_album_url}
                  href={@export_album_url}
                  target="_blank"
                  class="text-xs link link-primary"
                >
                  View album ↗
                </a>
              </div>
            <% !@current_scope -> %>
              <.link href={~p"/users/log-in"} class="btn btn-primary btn-sm gap-2">
                <.icon name="hero-user" class="size-4" /> Log in to save
              </.link>
            <% !has_google_token?(@current_scope) -> %>
              <.link href={~p"/auth/google"} class="btn btn-primary btn-sm gap-2">
                <.icon name="hero-photo" class="size-4" /> Connect Google Photos
              </.link>
            <% @catalog_items == [] -> %>
              <button class="btn btn-primary btn-sm gap-2" disabled>
                <.icon name="hero-photo" class="size-4" /> Save to Google Photos
              </button>
            <% true -> %>
              <button
                class="btn btn-primary btn-sm gap-2"
                phx-click="export_to_google_photos"
                phx-disable-with="Starting…"
              >
                <.icon name="hero-photo" class="size-4" /> Save to Google Photos
              </button>
          <% end %>
        </div>
      </div>

      <%!-- Items grid --%>
      <div :if={@catalog_items == []} class="card bg-base-200 p-16 text-center">
        <.icon name="hero-photo" class="size-16 mx-auto text-base-content/30" />
        <p class="mt-4 text-base-content/50">No items in this catalog yet.</p>
      </div>

      <div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        <div
          :for={item <- @catalog_items}
          id={"item-#{item.id}"}
          class="card bg-base-200 overflow-hidden group cursor-pointer"
          phx-click="open_lightbox"
          phx-value-item-id={item.id}
        >
          <figure class="aspect-video bg-base-300">
            <img
              :if={item.processed_key}
              src={Storage.get_url(item.processed_key)}
              class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              loading="lazy"
            />
          </figure>
          <div class="card-body p-3">
            <p class="text-xs font-medium truncate">{item.title}</p>
            <p :if={item.author} class="text-xs text-base-content/50 truncate">{item.author}</p>
          </div>
        </div>
      </div>
    </div>

    <%!-- Lightbox --%>
    <div
      :if={@lightbox_item}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_lightbox"
    >
      <div class="modal-box max-w-5xl w-full p-0 overflow-hidden">
        <figure class="bg-base-300">
          <img
            :if={@lightbox_item.processed_key}
            src={Storage.get_url(@lightbox_item.processed_key)}
            class="w-full object-contain max-h-[70vh]"
          />
        </figure>
        <div class="p-4 flex items-start justify-between gap-4">
          <div>
            <p class="font-semibold">{@lightbox_item.title}</p>
            <p :if={@lightbox_item.author} class="text-sm text-base-content/60">
              {@lightbox_item.author}
            </p>
            <p :if={@lightbox_item.copyright} class="text-xs text-base-content/40 mt-1">
              {@lightbox_item.copyright}
            </p>
          </div>
          <button class="btn btn-ghost btn-sm btn-circle shrink-0" phx-click="close_lightbox">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_lightbox"></div>
    </div>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    catalog = Catalog.get_catalog_by_slug!(slug)
    items = Catalog.list_catalog_items(catalog)

    Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "export:#{catalog.id}")

    {:ok,
     socket
     |> assign(:page_title, catalog.name)
     |> assign(:catalog, catalog)
     |> assign(:catalog_items, items)
     |> assign(:lightbox_item, nil)
     |> assign(:export_job_id, nil)
     |> assign(:export_done, false)
     |> assign(:export_album_url, nil)
     |> assign(:export_progress, 0)
     |> assign(:export_total, length(items))}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_lightbox", %{"item-id" => item_id}, socket) do
    item_id = String.to_integer(item_id)
    item = Enum.find(socket.assigns.catalog_items, &(&1.id == item_id))
    {:noreply, assign(socket, :lightbox_item, item)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_item, nil)}
  end

  def handle_event("export_to_google_photos", _params, socket) do
    user = socket.assigns.current_scope.user
    catalog = socket.assigns.catalog

    {:ok, job} =
      %{catalog_id: catalog.id, user_id: user.id}
      |> ScientiaCognita.Workers.ExportAlbumWorker.new()
      |> Oban.insert()

    {:noreply,
     socket
     |> assign(:export_job_id, job.id)
     |> assign(:export_progress, 0)
     |> assign(:export_total, length(socket.assigns.catalog_items))}
  end

  # ---------------------------------------------------------------------------
  # PubSub messages from ExportAlbumWorker
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:export_progress, %{uploaded: n, total: t}}, socket) do
    {:noreply, socket |> assign(:export_progress, n) |> assign(:export_total, t)}
  end

  def handle_info({:export_done, %{album_url: url}}, socket) do
    {:noreply,
     socket
     |> assign(:export_job_id, nil)
     |> assign(:export_done, true)
     |> assign(:export_album_url, url)}
  end

  def handle_info({:export_failed, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:export_job_id, nil)
     |> put_flash(:error, "Export failed. Please try again.")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp has_google_token?(nil), do: false
  defp has_google_token?(scope), do: not is_nil(scope.user.google_access_token)
end
