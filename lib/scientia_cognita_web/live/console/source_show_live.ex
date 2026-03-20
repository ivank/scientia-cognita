defmodule ScientiaCognitaWeb.Console.SourceShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.{Catalog, Storage}
  alias ScientiaCognita.Workers.{
    FetchPageWorker,
    DownloadImageWorker,
    ProcessImageWorker,
    ColorAnalysisWorker,
    RenderWorker
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">

      <%!-- Header --%>
      <div class="flex items-start justify-between gap-4">
        <div>
          <div class="flex items-center gap-2 text-sm text-base-content/50 mb-1">
            <.link navigate={~p"/console/sources"} class="hover:text-base-content">Sources</.link>
            <.icon name="hero-chevron-right" class="size-3" />
            <span>{@source.name}</span>
          </div>
          <h1 class="text-2xl font-bold flex items-center gap-3">
            {@source.name}
            <.status_badge status={@source.status} />
          </h1>
          <p class="text-sm text-base-content/50 mt-1 font-mono">{@source.url}</p>
        </div>

        <div class="flex gap-2 shrink-0">
          <button
            :if={@source.status == "failed"}
            class="btn btn-warning btn-sm gap-2"
            phx-click="restart_source"
            phx-disable-with="Restarting…"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            Restart
          </button>
          <button
            :if={@source.status == "done" and @failed_count > 0}
            class="btn btn-warning btn-sm gap-2"
            phx-click="retry_failed_items"
            phx-disable-with="Retrying…"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            Retry {@failed_count} failed
          </button>
          <button
            class="btn btn-error btn-sm gap-2"
            phx-click="confirm_delete"
          >
            <.icon name="hero-trash" class="size-4" />
            Delete
          </button>
        </div>
      </div>

      <%!-- Error message --%>
      <div :if={@source.error} class="alert alert-error text-sm">
        <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
        <span>{@source.error}</span>
      </div>

      <%!-- Progress stats --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <.stat_card label="Pages fetched" value={@source.pages_fetched} />
        <.stat_card label="Items found" value={@source.total_items} />
        <.stat_card label="Ready" value={@status_counts["ready"] || 0} class="text-success" />
        <.stat_card label="Failed" value={@failed_count} class={if @failed_count > 0, do: "text-error"} />
      </div>

      <%!-- Progress bar --%>
      <div :if={@source.total_items > 0} class="space-y-1">
        <div class="flex justify-between text-xs text-base-content/60">
          <span>Processing items</span>
          <span>{@status_counts["ready"] || 0} / {@source.total_items} ready</span>
        </div>
        <div class="w-full bg-base-300 rounded-full h-2">
          <div
            class="bg-success h-2 rounded-full transition-all duration-500"
            style={"width: #{progress_pct(@status_counts["ready"] || 0, @source.total_items)}%"}
          >
          </div>
        </div>
        <div class="flex gap-4 text-xs text-base-content/50 mt-1">
          <span :for={{status, count} <- sorted_status_counts(@status_counts)} :if={count > 0}>
            <.status_badge status={status} /> {count}
          </span>
        </div>
      </div>

      <%!-- Item grid (ready items only) --%>
      <div :if={@ready_items != []} class="space-y-3">
        <h2 class="font-semibold">Ready Items</h2>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          <div :for={item <- @ready_items} class="card bg-base-200 overflow-hidden">
            <figure class="aspect-video bg-base-300">
              <img
                :if={item.processed_key}
                src={Storage.get_url(item.processed_key)}
                class="w-full h-full object-cover"
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

      <%!-- Failed items --%>
      <div :if={@failed_items != []} class="space-y-3">
        <h2 class="font-semibold text-error">Failed Items ({@failed_count})</h2>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Title</th>
                <th>Stage</th>
                <th>Error</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @failed_items} id={"item-#{item.id}"}>
                <td class="max-w-xs truncate">{item.title}</td>
                <td>
                  <span class="badge badge-ghost badge-sm">
                    {if item.storage_key, do: "processing", else: "download"}
                  </span>
                  <span :if={MapSet.member?(@stuck_ids, item.id)} class="badge badge-warning badge-sm ml-1">
                    discarded
                  </span>
                </td>
                <td class="text-xs text-base-content/50 max-w-sm truncate">
                  {item.error || "Job discarded after maximum attempts — retry to continue"}
                </td>
                <td>
                  <button
                    class="btn btn-ghost btn-xs gap-1"
                    phx-click="retry_item"
                    phx-value-item-id={item.id}
                    phx-disable-with="…"
                  >
                    <.icon name="hero-arrow-path" class="size-3" />
                    Retry
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

    </div>

    <%!-- Delete confirmation modal --%>
    <div
      :if={@show_delete_modal}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="cancel_delete"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg text-error">Delete source?</h3>
        <p class="mt-3 text-base-content/80">
          This will permanently delete <span class="font-semibold">{@source.name}</span>
          and all <span class="font-semibold">{@source.total_items} items</span> associated with it,
          including all stored images. This cannot be undone.
        </p>
        <div class="modal-action">
          <button class="btn btn-ghost" phx-click="cancel_delete">Cancel</button>
          <button
            class="btn btn-error"
            phx-click="delete_source"
            phx-disable-with="Deleting…"
          >
            Delete source and all items
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_delete"></div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    source = Catalog.get_source!(id)
    Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "source:#{id}")

    {:ok, socket |> assign(:show_delete_modal, false) |> assign_source_data(source)}
  end

  @impl true
  def handle_info({:source_updated, source}, socket) do
    {:noreply, assign_source_data(socket, source)}
  end

  def handle_info({:item_updated, _item}, socket) do
    # Reload all item stats when any item changes
    source = Catalog.get_source!(socket.assigns.source.id)
    {:noreply, assign_source_data(socket, source)}
  end

  @impl true
  def handle_event("restart_source", _, socket) do
    source = socket.assigns.source

    {:ok, source} = Catalog.update_source_status(source, "pending", error: nil)
    Catalog.update_source_progress(source, %{pages_fetched: 0, total_items: 0, next_page_url: nil})

    %{source_id: source.id}
    |> FetchPageWorker.new()
    |> Oban.insert()

    {:noreply,
     socket
     |> assign_source_data(Catalog.get_source!(source.id))
     |> put_flash(:info, "Crawl restarted")}
  end

  def handle_event("retry_item", %{"item-id" => item_id}, socket) do
    item = Catalog.get_item!(item_id)

    {status, worker} =
      cond do
        is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
        is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
        is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
        true -> {"render", RenderWorker}
      end

    {:ok, _} = Catalog.update_item_status(item, status, error: nil)
    %{item_id: item.id} |> worker.new() |> Oban.insert()

    source = Catalog.get_source!(socket.assigns.source.id)
    {:noreply, assign_source_data(socket, source)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("delete_source", _, socket) do
    {:ok, _} = Catalog.delete_source_with_storage(socket.assigns.source)

    {:noreply,
     socket
     |> put_flash(:info, "Source \"#{socket.assigns.source.name}\" deleted.")
     |> push_navigate(to: ~p"/console/sources")}
  end

  def handle_event("retry_failed_items", _, socket) do
    Enum.each(socket.assigns.failed_items, fn item ->
      {status, worker} =
        cond do
          is_nil(item.storage_key) -> {"pending", DownloadImageWorker}
          is_nil(item.processed_key) -> {"processing", ProcessImageWorker}
          is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
          true -> {"render", RenderWorker}
        end

      {:ok, _} = Catalog.update_item_status(item, status, error: nil)
      %{item_id: item.id} |> worker.new() |> Oban.insert()
    end)

    source = Catalog.get_source!(socket.assigns.source.id)

    {:noreply,
     socket
     |> assign_source_data(source)
     |> put_flash(:info, "Retrying #{length(socket.assigns.failed_items)} items")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp assign_source_data(socket, source) do
    all_items = Catalog.list_items_by_source(source)
    stuck_ids = Catalog.list_stuck_item_ids(source) |> MapSet.new()

    status_counts = Enum.frequencies_by(all_items, & &1.status)

    failed_items =
      Enum.filter(all_items, fn item ->
        item.status == "failed" or MapSet.member?(stuck_ids, item.id)
      end)

    ready_items = Enum.filter(all_items, &(&1.status == "ready"))

    socket
    |> assign(:source, source)
    |> assign(:stuck_ids, stuck_ids)
    |> assign(:status_counts, status_counts)
    |> assign(:failed_items, failed_items)
    |> assign(:failed_count, length(failed_items))
    |> assign(:ready_items, ready_items)
  end

  defp progress_pct(0, _), do: 0
  defp progress_pct(ready, total), do: Float.round(ready / total * 100, 1)

  defp sorted_status_counts(counts) do
    order = ~w(pending downloading processing color_analysis render ready failed)
    Enum.sort_by(counts, fn {status, _} -> Enum.find_index(order, &(&1 == status)) || 99 end)
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4">
      <div class={"text-2xl font-bold #{Map.get(assigns, :class, "")}"}>{@value}</div>
      <div class="text-xs text-base-content/50 mt-0.5">{@label}</div>
    </div>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={"badge badge-xs #{status_class(@status)}"}>{@status}</span>
    """
  end

  defp status_class("pending"), do: "badge-ghost"
  defp status_class("fetching"), do: "badge-warning animate-pulse"
  defp status_class("extracting"), do: "badge-warning animate-pulse"
  defp status_class("done"), do: "badge-success"
  defp status_class("ready"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class("downloading"), do: "badge-info"
  defp status_class("processing"), do: "badge-info"
  defp status_class("color_analysis"), do: "badge-info"
  defp status_class("render"), do: "badge-info"
  defp status_class(_), do: "badge-ghost"
end
