defmodule ScientiaCognitaWeb.Console.CatalogShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Catalog.Source
  alias ScientiaCognita.Uploaders.ItemImageUploader

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.breadcrumb items={[
        %{label: "Console", href: ~p"/console"},
        %{label: "Catalogs", href: ~p"/console/catalogs"},
        %{label: @catalog.name}
      ]} />
      <.page_header title={@catalog.name} subtitle={@catalog.description}>
        <:action>
          <button
            class="btn btn-primary btn-sm"
            phx-click="open_picker"
            phx-disable-with="Loading…"
          >
            Add Items
          </button>
        </:action>
      </.page_header>
      <p class="font-mono text-xs text-base-content/40 -mt-4 mb-4">/{@catalog.slug}</p>

      <%!-- Items grid --%>
      <div :if={@catalog_items == []} class="card bg-base-200 p-12 text-center">
        <.icon name="hero-photo" class="size-12 mx-auto text-base-content/30" />
        <p class="mt-3 text-base-content/50">No items yet. Add items from a source.</p>
        <button class="btn btn-primary btn-sm mt-4 mx-auto" phx-click="open_picker">
          Add Items
        </button>
      </div>

      <div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        <div
          :for={item <- @catalog_items}
          id={"catalog-item-#{item.id}"}
          class="card bg-base-200 overflow-hidden group"
        >
          <figure class="aspect-video bg-base-300 relative">
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
            <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
              <button
                class="btn btn-error btn-xs"
                phx-click="remove_item"
                phx-value-item-id={item.id}
              >
                Remove
              </button>
            </div>
          </figure>
          <div class="card-body p-3">
            <p class="text-xs font-medium truncate">{item.title}</p>
            <p :if={item.author} class="text-xs text-base-content/50 truncate">{item.author}</p>
          </div>
        </div>
      </div>
    </div>

    <%!-- Item Picker modal --%>
    <div
      :if={@show_picker}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_picker"
    >
      <div class="modal-box max-w-4xl w-full">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg text-base-content font-serif-display">Add Items to Catalog</h3>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_picker">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <%!-- Source autocomplete --%>
        <div class="form-control mb-4">
          <label class="label pb-1">
            <span class="label-text text-sm">Source</span>
          </label>
          <div>
            <%!-- Source is selected --%>
            <div
              :if={@picker_source_id}
              class="flex items-center gap-2 input input-bordered h-10 px-3"
            >
              <.icon name="hero-check-circle" class="size-4 text-success shrink-0" />
              <span class="flex-1 text-sm truncate">{@picker_source_name}</span>
              <button
                type="button"
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="clear_picker_source"
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </div>

            <%!-- No source selected: live search --%>
            <div :if={!@picker_source_id}>
              <form phx-change="search_sources">
                <input
                  type="text"
                  name="query"
                  value={@picker_query}
                  class="input input-bordered w-full"
                  placeholder="Search sources…"
                  phx-debounce="100"
                  autocomplete="off"
                  phx-mounted={JS.focus()}
                />
              </form>
              <div
                :if={@picker_suggestions != []}
                class="mt-1 border border-base-300 rounded-lg overflow-hidden"
              >
                <button
                  :for={s <- @picker_suggestions}
                  type="button"
                  class="flex items-center justify-between w-full px-4 py-2.5 text-sm hover:bg-base-200 transition-colors"
                  phx-click="pick_source"
                  phx-value-source-id={s.id}
                >
                  <span class="truncate">{Source.display_name(s)}</span>
                  <span class="text-xs text-base-content/40 shrink-0 ml-4">
                    {s.total_items} items
                  </span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Item grid --%>
        <div :if={@picker_source_id} class="space-y-4">
          <div class="flex items-center justify-between text-sm">
            <span class="text-base-content/60">
              {length(@picker_items)} ready items —
              <span class="text-primary">{MapSet.size(@picker_in_catalog)} already in catalog</span>
            </span>
            <div class="flex gap-2">
              <button class="btn btn-ghost btn-xs" phx-click="select_all_new">
                Select all new
              </button>
              <button class="btn btn-ghost btn-xs" phx-click="clear_selection">
                Deselect all
              </button>
            </div>
          </div>

          <div class="grid grid-cols-3 sm:grid-cols-4 gap-2 max-h-96 overflow-y-auto pr-1">
            <label
              :for={item <- @picker_items}
              class={[
                "card bg-base-300 overflow-hidden cursor-pointer relative",
                MapSet.member?(@picker_in_catalog, item.id) && "ring-2 ring-success"
              ]}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-primary checkbox-sm absolute top-1.5 left-1.5 z-10 bg-base-100/80"
                checked={MapSet.member?(@picker_selected, item.id)}
                phx-click="toggle_item"
                phx-value-item-id={item.id}
              />
              <figure class="aspect-video bg-base-200">
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
              </figure>
              <div class="p-1.5">
                <p class="text-xs truncate">{item.title}</p>
                <span
                  :if={MapSet.member?(@picker_in_catalog, item.id)}
                  class="badge badge-success badge-xs"
                >
                  in catalog
                </span>
              </div>
            </label>
          </div>

          <div class="modal-action pt-0">
            <span class="text-sm text-base-content/60 mr-auto">
              {MapSet.size(@picker_selected)} selected
            </span>
            <button class="btn btn-ghost" phx-click="close_picker">Cancel</button>
            <button
              class="btn btn-primary"
              phx-click="add_selected"
              phx-disable-with="Adding…"
              disabled={MapSet.size(@picker_selected) == 0}
            >
              Add {MapSet.size(@picker_selected)} items
            </button>
          </div>
        </div>

        <div :if={!@picker_source_id and @picker_suggestions == []} class="text-center py-8 text-base-content/40">
          No sources with ready items found.
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_picker"></div>
    </div>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    catalog = Catalog.get_catalog_by_slug!(slug)
    items = Catalog.list_catalog_items(catalog)

    {:ok,
     socket
     |> assign(:catalog, catalog)
     |> assign(:catalog_items, items)
     |> assign(:show_picker, false)
     |> assign(:picker_sources, [])
     |> assign(:picker_query, "")
     |> assign(:picker_suggestions, [])
     |> assign(:picker_source_id, nil)
     |> assign(:picker_source_name, nil)
     |> assign(:picker_items, [])
     |> assign(:picker_in_catalog, MapSet.new())
     |> assign(:picker_selected, MapSet.new())}
  end

  # ---------------------------------------------------------------------------
  # Events — catalog
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("remove_item", %{"item-id" => item_id}, socket) do
    Catalog.remove_item_from_catalog(socket.assigns.catalog, String.to_integer(item_id))

    items = Catalog.list_catalog_items(socket.assigns.catalog)
    {:noreply, assign(socket, :catalog_items, items)}
  end

  # ---------------------------------------------------------------------------
  # Events — item picker
  # ---------------------------------------------------------------------------

  def handle_event("open_picker", _, socket) do
    sources = Catalog.list_sources_with_ready_items()

    {:noreply,
     assign(socket,
       show_picker: true,
       picker_sources: sources,
       picker_query: "",
       picker_suggestions: filter_suggestions(sources, ""),
       picker_source_id: nil,
       picker_source_name: nil,
       picker_items: [],
       picker_in_catalog: MapSet.new(),
       picker_selected: MapSet.new()
     )}
  end

  def handle_event("close_picker", _, socket) do
    {:noreply,
     assign(socket,
       show_picker: false,
       picker_query: "",
       picker_suggestions: [],
       picker_source_id: nil,
       picker_source_name: nil,
       picker_items: [],
       picker_in_catalog: MapSet.new(),
       picker_selected: MapSet.new()
     )}
  end

  def handle_event("search_sources", %{"query" => query}, socket) do
    suggestions = filter_suggestions(socket.assigns.picker_sources, query)
    {:noreply, assign(socket, picker_query: query, picker_suggestions: suggestions)}
  end

  def handle_event("pick_source", %{"source-id" => source_id}, socket) do
    source_id = String.to_integer(source_id)
    source = Catalog.get_source!(source_id)

    {items, in_catalog} =
      Catalog.list_ready_items_for_picker(source_id, socket.assigns.catalog.id)

    # Pre-select every item not already in the catalog
    pre_selected =
      items
      |> Enum.reject(&MapSet.member?(in_catalog, &1.id))
      |> MapSet.new(& &1.id)

    {:noreply,
     assign(socket,
       picker_source_id: source_id,
       picker_source_name: Source.display_name(source),
       picker_suggestions: [],
       picker_items: items,
       picker_in_catalog: in_catalog,
       picker_selected: pre_selected
     )}
  end

  def handle_event("clear_picker_source", _, socket) do
    {:noreply,
     assign(socket,
       picker_source_id: nil,
       picker_source_name: nil,
       picker_items: [],
       picker_in_catalog: MapSet.new(),
       picker_selected: MapSet.new(),
       picker_query: "",
       picker_suggestions: filter_suggestions(socket.assigns.picker_sources, "")
     )}
  end

  def handle_event("toggle_item", %{"item-id" => item_id}, socket) do
    item_id = String.to_integer(item_id)

    new_selected =
      if MapSet.member?(socket.assigns.picker_selected, item_id) do
        MapSet.delete(socket.assigns.picker_selected, item_id)
      else
        MapSet.put(socket.assigns.picker_selected, item_id)
      end

    {:noreply, assign(socket, :picker_selected, new_selected)}
  end

  def handle_event("select_all_new", _, socket) do
    new_ids =
      socket.assigns.picker_items
      |> Enum.reject(&MapSet.member?(socket.assigns.picker_in_catalog, &1.id))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, assign(socket, :picker_selected, new_ids)}
  end

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :picker_selected, MapSet.new())}
  end

  def handle_event("add_selected", _, socket) do
    item_ids = MapSet.to_list(socket.assigns.picker_selected)
    Catalog.add_items_to_catalog(socket.assigns.catalog, item_ids)

    catalog = socket.assigns.catalog
    items = Catalog.list_catalog_items(catalog)

    {picker_items, in_catalog} =
      if socket.assigns.picker_source_id do
        Catalog.list_ready_items_for_picker(socket.assigns.picker_source_id, catalog.id)
      else
        {[], MapSet.new()}
      end

    # After adding, re-compute pre-selection (remaining new items)
    pre_selected =
      picker_items
      |> Enum.reject(&MapSet.member?(in_catalog, &1.id))
      |> MapSet.new(& &1.id)

    {:noreply,
     socket
     |> assign(:catalog_items, items)
     |> assign(:picker_items, picker_items)
     |> assign(:picker_in_catalog, in_catalog)
     |> assign(:picker_selected, pre_selected)
     |> put_flash(:info, "Added #{length(item_ids)} items to catalog")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns up to 8 sources when query is empty; filters by display name otherwise.
  defp filter_suggestions(sources, "") do
    Enum.take(sources, 8)
  end

  defp filter_suggestions(sources, query) do
    q = String.downcase(query)

    Enum.filter(sources, fn s ->
      s |> Source.display_name() |> String.downcase() |> String.contains?(q)
    end)
  end
end
