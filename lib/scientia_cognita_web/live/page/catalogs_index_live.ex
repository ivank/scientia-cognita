defmodule ScientiaCognitaWeb.Page.CatalogsIndexLive do
  use ScientiaCognitaWeb, :live_view

  alias ScientiaCognita.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Full-width dark hero --%>
      <div class="bg-[oklch(13%_0.025_222)] px-4 sm:px-8 pt-14 pb-16">
        <div class="max-w-6xl mx-auto">
          <p class="text-[oklch(64%_0.115_218)] text-xs font-semibold tracking-[0.2em] uppercase mb-5">
            Collections
          </p>
          <h1 class="font-serif-display text-5xl lg:text-7xl text-white leading-[1.05] tracking-tight">
            Curated Catalogs
          </h1>
          <p class="text-white/50 text-lg mt-5 max-w-xl leading-relaxed">
            Explore hand-picked image collections. Save any catalog directly to your Google Photos.
          </p>
        </div>
      </div>

      <%!-- How it works — XKCD-style comic explainer --%>
      <div class="border-b border-base-300 bg-base-100 py-12 px-4">
        <div class="max-w-5xl mx-auto">
          <p class="text-center text-base-content/60 text-base mb-8 max-w-2xl mx-auto leading-relaxed">
            Turn your TV screensaver into a daily education. Each catalog syncs to your Google Photos
            library so your TV teaches you something new every time you leave the room.
          </p>

          <%!-- Comic panels: horizontal scroll on mobile, side-by-side on md+ --%>
          <div class="overflow-x-auto -mx-4 px-4">
            <img
              src={~p"/images/explanation.svg"}
              alt="Explanation of what scientia cognita is all about"
            />
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-4 py-10">
        <div :if={@catalogs == []} class="card bg-base-200 p-16 text-center">
          <.icon name="hero-rectangle-stack" class="size-16 mx-auto text-base-content/30" />
          <p class="mt-4 text-base-content/50">No catalogs published yet. Check back soon.</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <.link
            :for={catalog <- @catalogs}
            navigate={~p"/catalogs/#{catalog.slug}"}
            class="card bg-base-200 shadow-sm hover:shadow-lg transition-shadow overflow-hidden group"
          >
            <%!-- Cover image from first item --%>
            <figure :if={Map.get(@cover_images, catalog.id)} class="aspect-[4/3] bg-base-300">
              <img
                src={Map.get(@cover_images, catalog.id)}
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
              />
            </figure>
            <figure
              :if={!Map.get(@cover_images, catalog.id)}
              class="aspect-[4/3] bg-base-300 flex items-center justify-center"
            >
              <.icon name="hero-photo" class="size-12 text-base-content/20" />
            </figure>
            <div class="card-body p-5">
              <h2 class="card-title text-lg font-serif-display font-semibold">{catalog.name}</h2>
              <p :if={catalog.description} class="text-sm text-base-content/60 line-clamp-2 mt-0.5">
                {catalog.description}
              </p>
              <div class="flex items-center justify-between mt-3">
                <span class="font-mono text-xs text-base-content/40">{catalog.slug}</span>
                <span class="badge badge-primary badge-outline badge-sm">
                  {Map.get(@item_counts, catalog.id, 0)} items
                </span>
              </div>
            </div>
          </.link>
        </div>
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
