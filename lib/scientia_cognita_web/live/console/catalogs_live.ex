defmodule ScientiaCognitaWeb.Console.CatalogsLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold">Catalogs</h1>
      <p class="text-base-content/60 mt-1">Coming soon — Phase 7</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
