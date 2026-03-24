defmodule ScientiaCognitaWeb.Console.CatalogsLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Catalog.Catalog, as: CatalogSchema

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.breadcrumb items={[
        %{label: "Console", href: ~p"/console"},
        %{label: "Catalogs"}
      ]} />
      <div class="flex items-center justify-between">
        <div>
          <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
            Catalogs
          </h1>
          <p class="text-neutral text-sm mt-1">Curated collections published to Google Photos</p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="open_new_modal">
          <.icon name="hero-plus" class="size-4" /> New Catalog
        </button>
      </div>

      <div :if={@catalogs == []} class="card bg-base-200 p-12 text-center">
        <.icon name="hero-rectangle-stack" class="size-12 mx-auto text-base-content/30" />
        <p class="mt-3 text-base-content/50">No catalogs yet.</p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <.link
          :for={catalog <- @catalogs}
          navigate={~p"/console/catalogs/#{catalog.slug}"}
          class="card bg-base-200 hover:bg-base-300 transition-colors"
        >
          <div class="card-body">
            <h2 class="card-title text-base">{catalog.name}</h2>
            <p :if={catalog.description} class="text-sm text-base-content/60 line-clamp-2">
              {catalog.description}
            </p>
            <div class="flex items-center justify-between mt-3">
              <span class="font-mono text-xs text-base-content/40">{catalog.slug}</span>
              <span class="badge badge-ghost badge-sm">
                {Map.get(@item_counts, catalog.id, 0)} items
              </span>
            </div>
          </div>
        </.link>
      </div>
    </div>

    <%!-- New Catalog modal --%>
    <div
      :if={@show_new_modal}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_modal"
    >
      <div class="modal-box">
        <h3 style="font-family: var(--sc-font-serif);" class="text-lg text-base-content">New Catalog</h3>

        <.form for={@form} phx-submit="create_catalog" phx-change="validate" class="mt-4 space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Name</span></label>
            <.input field={@form[:name]} placeholder="e.g. Summer Landscapes" />
          </div>
          <div class="form-control">
            <label class="label">
              <span class="label-text">Slug</span>
              <span class="label-text-alt text-base-content/40">auto-generated, can edit</span>
            </label>
            <.input field={@form[:slug]} placeholder="summer-landscapes" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Description</span></label>
            <.input
              field={@form[:description]}
              type="textarea"
              rows="3"
              placeholder="Optional description…"
            />
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
            <button type="submit" class="btn btn-primary">Create</button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    catalogs = Catalog.list_catalogs()
    item_counts = Map.new(catalogs, &{&1.id, Catalog.count_catalog_items(&1)})

    {:ok,
     socket
     |> assign(:catalogs, catalogs)
     |> assign(:item_counts, item_counts)
     |> assign(:show_new_modal, false)
     |> assign(:form, to_form(Catalog.change_catalog(%CatalogSchema{})))}
  end

  @impl true
  def handle_event("open_new_modal", _, socket) do
    {:noreply, assign(socket, :show_new_modal, true)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_new_modal, false)}
  end

  def handle_event("validate", %{"catalog" => params}, socket) do
    form =
      %CatalogSchema{}
      |> Catalog.change_catalog(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create_catalog", %{"catalog" => params}, socket) do
    case Catalog.create_catalog(params) do
      {:ok, catalog} ->
        catalogs = Catalog.list_catalogs()
        item_counts = Map.new(catalogs, &{&1.id, Catalog.count_catalog_items(&1)})

        {:noreply,
         socket
         |> assign(:catalogs, catalogs)
         |> assign(:item_counts, item_counts)
         |> assign(:show_new_modal, false)
         |> assign(:form, to_form(Catalog.change_catalog(%CatalogSchema{})))
         |> put_flash(:info, "Catalog \"#{catalog.name}\" created")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
