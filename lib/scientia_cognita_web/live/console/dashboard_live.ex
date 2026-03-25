defmodule ScientiaCognitaWeb.Console.DashboardLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.breadcrumb items={[%{label: "Console", href: ~p"/console"}, %{label: "Dashboard"}]} />
      <div>
        <h1 class="text-xl text-base-content font-serif-display">
          Dashboard
        </h1>
        <p class="text-neutral text-sm mt-1">Welcome to the Scientia Cognita console.</p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.link
          navigate={~p"/console/sources"}
          class="card bg-base-200 hover:bg-base-300 transition-colors"
        >
          <div class="card-body">
            <.icon name="hero-globe-alt" class="size-8 text-primary" />
            <h2 class="card-title mt-2">Sources</h2>
            <p class="text-sm text-base-content/60">Manage content sources</p>
          </div>
        </.link>

        <.link
          navigate={~p"/console/catalogs"}
          class="card bg-base-200 hover:bg-base-300 transition-colors"
        >
          <div class="card-body">
            <.icon name="hero-rectangle-stack" class="size-8 text-primary" />
            <h2 class="card-title mt-2">Catalogs</h2>
            <p class="text-sm text-base-content/60">Curate image collections</p>
          </div>
        </.link>

        <.link
          navigate={~p"/console/users"}
          class="card bg-base-200 hover:bg-base-300 transition-colors"
        >
          <div class="card-body">
            <.icon name="hero-users" class="size-8 text-primary" />
            <h2 class="card-title mt-2">Users</h2>
            <p class="text-sm text-base-content/60">Manage user accounts</p>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
