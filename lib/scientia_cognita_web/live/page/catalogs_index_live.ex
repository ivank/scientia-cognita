defmodule ScientiaCognitaWeb.Page.CatalogsIndexLive do
  use ScientiaCognitaWeb, :live_view

  alias ScientiaCognita.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-10 space-y-8">
      <div class="text-center space-y-2">
        <h1 class="text-4xl font-bold">Curated Catalogs</h1>
        <p class="text-base-content/60 max-w-xl mx-auto">
          Explore hand-picked image collections. Save any catalog directly to your Google Photos.
        </p>
      </div>

      <div :if={@catalogs == []} class="card bg-base-200 p-16 text-center">
        <.icon name="hero-rectangle-stack" class="size-16 mx-auto text-base-content/30" />
        <p class="mt-4 text-base-content/50">No catalogs published yet. Check back soon.</p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        <.link
          :for={catalog <- @catalogs}
          navigate={~p"/catalogs/#{catalog.slug}"}
          class="card bg-base-200 hover:bg-base-300 transition-colors overflow-hidden group"
        >
          <%!-- Cover image from first item --%>
          <figure :if={Map.get(@cover_images, catalog.id)} class="aspect-video bg-base-300">
            <img
              src={Map.get(@cover_images, catalog.id)}
              class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
            />
          </figure>
          <figure
            :if={!Map.get(@cover_images, catalog.id)}
            class="aspect-video bg-base-300 flex items-center justify-center"
          >
            <.icon name="hero-photo" class="size-12 text-base-content/20" />
          </figure>
          <div class="card-body p-4">
            <h2 class="card-title text-base">{catalog.name}</h2>
            <p :if={catalog.description} class="text-sm text-base-content/60 line-clamp-2">
              {catalog.description}
            </p>
            <div class="flex items-center justify-between mt-2">
              <span class="font-mono text-xs text-base-content/40">{catalog.slug}</span>
              <span class="badge badge-ghost badge-sm">
                {Map.get(@item_counts, catalog.id, 0)} items
              </span>
            </div>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    catalogs = Catalog.list_catalogs()
    item_counts = Map.new(catalogs, &{&1.id, Catalog.count_catalog_items(&1)})
    cover_images = Map.new(catalogs, &{&1.id, Catalog.get_catalog_cover_url(&1)})

    {:ok,
     socket
     |> assign(:page_title, "Catalogs")
     |> assign(:catalogs, catalogs)
     |> assign(:item_counts, item_counts)
     |> assign(:cover_images, cover_images)}
  end
end
