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
            <.icon name="hero-arrow-path" class="size-4" /> Restart
          </button>
          <button
            :if={@source.status == "done" and @failed_count > 0}
            class="btn btn-warning btn-sm gap-2"
            phx-click="retry_failed_items"
            phx-disable-with="Retrying…"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Retry {@failed_count} failed
          </button>
          <button
            class="btn btn-error btn-sm gap-2"
            phx-click="confirm_delete"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
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
        <.stat_card
          label="Failed"
          value={@failed_count}
          class={if @failed_count > 0, do: "text-error"}
        />
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

      <%!-- Items table (all statuses) --%>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Error</th>
              <th></th>
            </tr>
          </thead>
          <tbody id="items-stream" phx-update="stream">
            <tr :for={{dom_id, item} <- @streams.items} id={dom_id}>
              <td class="max-w-xs truncate">{item.title}</td>
              <td>
                <.status_badge status={item.status} />
                <span
                  :if={MapSet.member?(@stuck_ids, item.id)}
                  class="badge badge-warning badge-sm ml-1"
                >
                  discarded
                </span>
              </td>
              <td class="text-xs text-base-content/50 max-w-sm truncate">
                {item.error}
              </td>
              <td>
                <button
                  class="btn btn-ghost btn-xs gap-1"
                  phx-click="select_item"
                  phx-value-id={item.id}
                  phx-disable-with="…"
                >
                  View
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <%!-- Item detail / edit modal --%>
    <div
      :if={@selected_item}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown={if @item_form, do: "cancel_edit", else: "close_item"}
    >
      <div class="modal-box max-w-2xl p-0 overflow-hidden">
        <figure class="aspect-video bg-base-300 w-full">
          <img
            :if={@selected_item.processed_key}
            src={Storage.get_url(@selected_item.processed_key)}
            class="w-full h-full object-contain"
          />
        </figure>

        <%!-- View mode --%>
        <div :if={!@item_form} class="p-6 space-y-4">
          <h3 class="font-bold text-lg leading-snug">{@selected_item.title}</h3>
          <p :if={@selected_item.description} class="text-sm text-base-content/80">
            {@selected_item.description}
          </p>
          <div class="flex flex-wrap gap-x-6 gap-y-2 text-xs text-base-content/50">
            <span :if={@selected_item.author}>
              <span class="font-medium text-base-content/70">Author</span>
              {@selected_item.author}
            </span>
            <span :if={@selected_item.copyright}>
              <span class="font-medium text-base-content/70">©</span>
              {@selected_item.copyright}
            </span>
          </div>
          <div :if={@selected_item.original_url} class="text-xs font-mono text-base-content/40 truncate">
            {@selected_item.original_url}
          </div>
          <div class="modal-action pt-2">
            <div class="flex gap-2 flex-1">
              <button
                class="btn btn-ghost btn-sm gap-1"
                phx-click="redownload_item"
                phx-value-id={@selected_item.id}
                phx-disable-with="…"
                title="Clear stored images and re-run the full pipeline from download"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Re-download
              </button>
              <button
                :if={@selected_item.processed_key}
                class="btn btn-ghost btn-sm gap-1"
                phx-click="rerender_item"
                phx-value-id={@selected_item.id}
                phx-disable-with="…"
                title="Re-run the render step using the existing processed image"
              >
                <.icon name="hero-paint-brush" class="size-4" /> Re-render
              </button>
            </div>
            <button class="btn btn-ghost btn-sm" phx-click="edit_item">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </button>
            <a
              :if={@selected_item.original_url}
              href={@selected_item.original_url}
              target="_blank"
              class="btn btn-primary btn-sm gap-1"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" /> Original
            </a>
            <button class="btn btn-ghost btn-sm" phx-click="close_item">Close</button>
          </div>
        </div>

        <%!-- Edit mode --%>
        <div :if={@item_form} class="p-6">
          <h3 class="font-semibold mb-4">Edit item</h3>
          <.form for={@item_form} phx-submit="save_item" phx-change="validate_item" class="space-y-4">
            <div class="form-control">
              <label class="label pb-1"><span class="label-text text-xs font-medium uppercase tracking-wide">Title</span></label>
              <.input field={@item_form[:title]} placeholder="Image title" />
            </div>
            <div class="form-control">
              <label class="label pb-1"><span class="label-text text-xs font-medium uppercase tracking-wide">Description</span></label>
              <.input field={@item_form[:description]} type="textarea" rows="3" placeholder="Caption or description" />
            </div>
            <div class="form-control">
              <label class="label pb-1"><span class="label-text text-xs font-medium uppercase tracking-wide">Image URL</span></label>
              <.input field={@item_form[:original_url]} type="url" placeholder="https://…" />
            </div>
            <div class="modal-action pt-0">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Saving…">Save</button>
            </div>
          </.form>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={if @item_form, do: "cancel_edit", else: "close_item"}></div>
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
          and all <span class="font-semibold">{@source.total_items} items</span>
          associated with it,
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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "source:#{id}")
    end

    all_items = Catalog.list_items_by_source(source)

    {:ok,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:selected_item, nil)
     |> assign(:item_form, nil)
     |> assign_source_stats(source)
     |> stream(:items, all_items)}
  end

  @impl true
  def handle_info({:source_updated, source}, socket) do
    # The broadcasted source already carries gemini_pages (embedded schema).
    {:noreply, assign_source_stats(socket, source)}
  end

  def handle_info({:item_updated, item}, socket) do
    {:noreply,
     socket
     |> stream_insert(:items, item)
     |> assign_source_stats(socket.assigns.source)}
  end

  @impl true
  def handle_event("restart_source", _, socket) do
    source = socket.assigns.source

    {:ok, source} = Catalog.reset_source(source)

    %{source_id: source.id}
    |> FetchPageWorker.new()
    |> Oban.insert()

    {:noreply,
     socket
     |> assign_source_stats(Catalog.get_source!(source.id))
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
    {:noreply, assign_source_stats(socket, source)}
  end

  def handle_event("select_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)
    {:noreply, socket |> assign(:selected_item, item) |> assign(:item_form, nil)}
  end

  def handle_event("close_item", _, socket) do
    {:noreply, socket |> assign(:selected_item, nil) |> assign(:item_form, nil)}
  end

  def handle_event("edit_item", _, socket) do
    form = socket.assigns.selected_item |> Catalog.change_item() |> to_form()
    {:noreply, assign(socket, :item_form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :item_form, nil)}
  end

  def handle_event("validate_item", %{"item" => params}, socket) do
    form =
      socket.assigns.selected_item
      |> Catalog.change_item(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :item_form, form)}
  end

  def handle_event("save_item", %{"item" => params}, socket) do
    case Catalog.update_item(socket.assigns.selected_item, params) do
      {:ok, item} ->
        source = Catalog.get_source!(socket.assigns.source.id)

        {:noreply,
         socket
         |> assign(:selected_item, item)
         |> assign(:item_form, nil)
         |> assign_source_stats(source)}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset))}
    end
  end

  def handle_event("redownload_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)
    # Clear stored images so DownloadImageWorker fetches fresh copies,
    # then let the worker chain run to ready automatically.
    {:ok, item} = Catalog.update_item_storage(item, %{storage_key: nil, processed_key: nil})
    {:ok, item} = Catalog.update_item_status(item, "pending", error: nil)
    %{item_id: item.id} |> DownloadImageWorker.new() |> Oban.insert()
    source = Catalog.get_source!(socket.assigns.source.id)

    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:item_form, nil)
     |> assign_source_stats(source)
     |> put_flash(:info, "Re-downloading item")}
  end

  def handle_event("rerender_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)
    # Put back to render state and enqueue RenderWorker — it completes to ready.
    {:ok, item} = Catalog.update_item_status(item, "render", error: nil)
    %{item_id: item.id} |> RenderWorker.new() |> Oban.insert()
    source = Catalog.get_source!(socket.assigns.source.id)

    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:item_form, nil)
     |> assign_source_stats(source)
     |> put_flash(:info, "Re-rendering item")}
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
    source = socket.assigns.source
    stuck_ids = socket.assigns.stuck_ids

    items_to_retry =
      Catalog.list_items_by_source(source)
      |> Enum.filter(fn item ->
        item.status == "failed" or MapSet.member?(stuck_ids, item.id)
      end)

    Enum.each(items_to_retry, fn item ->
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

    {:noreply,
     socket
     |> assign_source_stats(Catalog.get_source!(source.id))
     |> put_flash(:info, "Retrying #{length(items_to_retry)} items")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp assign_source_stats(socket, source) do
    status_counts = Catalog.count_items_by_status(source)
    stuck_ids = Catalog.list_stuck_item_ids(source) |> MapSet.new()

    socket
    |> assign(:source, source)
    |> assign(:status_counts, status_counts)
    |> assign(:failed_count, status_counts["failed"] || 0)
    |> assign(:stuck_ids, stuck_ids)
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
