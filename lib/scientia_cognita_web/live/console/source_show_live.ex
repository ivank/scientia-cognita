defmodule ScientiaCognitaWeb.Console.SourceShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.Catalog
  alias ScientiaCognita.Uploaders.ItemImageUploader
  alias ScientiaCognita.Catalog.Source

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
            <span>{Source.display_name(@source)}</span>
          </div>
          <h1 class="text-2xl font-bold flex items-center gap-3">
            {Source.display_name(@source)}
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
            :if={@discarded_count > 0}
            class="btn btn-warning btn-sm gap-2"
            phx-click="retry_discarded_items"
            phx-disable-with="Retrying…"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Retry {@discarded_count} discarded
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

      <%!-- Loading banner --%>
      <div :if={@source.status == "items_loading"} class="flex items-center gap-2 text-sm text-base-content/60">
        <span class="loading loading-spinner loading-sm"></span>
        Items are being loaded…
      </div>

      <%!-- Items table --%>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="w-20">Image</th>
              <th>Status</th>
              <th>Title</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody id="items" phx-update="stream">
            <tr
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              class={"cursor-pointer hover:bg-base-300/40 transition-colors #{row_class(item.status)}"}
              phx-click="select_item"
              phx-value-id={item.id}
            >
              <td class="p-1">
                <.item_thumbnail item={item} />
              </td>
              <td class="whitespace-nowrap">
                <.status_badge status={item.status} />
                <span
                  :if={MapSet.member?(@stuck_ids, item.id)}
                  class="badge badge-warning badge-sm ml-1"
                >
                  discarded
                </span>
              </td>
              <td class="max-w-xs">
                <p class="text-sm font-medium truncate">{item.title}</p>
              </td>
              <td class="max-w-sm">
                <p
                  :if={item.status != "failed"}
                  class="text-xs text-base-content/60 line-clamp-2"
                >
                  {item.description}
                </p>
                <p
                  :if={item.status in ["failed", "discarded"]}
                  class="text-xs text-error line-clamp-2"
                >
                  {item.error || item.description}
                </p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Gemini extraction panels --%>
      <div :if={@source.gemini_pages != []} class="space-y-2 pt-2">
        <h3 class="text-sm font-semibold text-base-content/60">Gemini Extraction Data</h3>
        <details
          :for={{page, idx} <- Enum.with_index(@source.gemini_pages, 1)}
          class="border border-base-300 rounded-lg overflow-hidden"
        >
          <summary class="flex items-center gap-2 px-4 py-2 cursor-pointer text-sm bg-base-200 hover:bg-base-300 select-none">
            <span class="font-medium">Page {idx}</span>
            <span :if={page.gallery_title}>· {page.gallery_title}</span>
            <span :if={page.gallery_description} class="text-base-content/50 truncate max-w-xs">
              — {String.slice(page.gallery_description || "", 0, 80)}
            </span>
            <span class="ml-auto text-base-content/40 shrink-0">{page.items_count} items</span>
          </summary>
          <pre class="text-xs overflow-auto max-h-96 bg-base-200 p-4 m-0">{gemini_page_json(page)}</pre>
        </details>
      </div>
    </div>

    <%!-- Item detail / edit modal --%>
    <div
      :if={@selected_item}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_item"
    >
      <div class="modal-box max-w-3xl p-0 overflow-hidden">
        <div class="flex max-h-[80vh]">
          <%!-- Left: status-aware image preview --%>
          <figure class="w-56 shrink-0 bg-base-300 self-stretch overflow-hidden relative">
            <%= cond do %>
              <% @selected_item.status in ~w(pending downloading) -> %>
                <div class="skeleton absolute inset-0 rounded-none"></div>
              <% @selected_item.status == "render" -> %>
                <img
                  :if={@selected_item.processed_image || @selected_item.original_image}
                  src={ItemImageUploader.url({@selected_item.processed_image || @selected_item.original_image, @selected_item})}
                  class="w-full h-full object-contain"
                />
                <div class="absolute inset-0 ring-2 ring-inset ring-primary animate-pulse pointer-events-none"></div>
              <% @selected_item.processed_image || @selected_item.original_image -> %>
                <img
                  src={ItemImageUploader.url({@selected_item.processed_image || @selected_item.original_image, @selected_item})}
                  class="w-full h-full object-contain"
                />
              <% true -> %>
            <% end %>
          </figure>

          <%!-- Right: scrollable fields + pinned action bar --%>
          <.form for={@item_form} phx-submit="save_item" phx-change="validate_item" class="flex-1 flex flex-col min-w-0 overflow-hidden">
            <div class="flex-1 overflow-y-auto p-5 space-y-4">
              <%!-- Full error (if any) --%>
              <div :if={@selected_item.error} class="alert alert-error text-sm">
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                <span>{@selected_item.error}</span>
              </div>

              <div class="form-control">
                <label class="label pb-1">
                  <span class="label-text text-xs font-medium uppercase tracking-wide">Title</span>
                </label>
                <.input field={@item_form[:title]} placeholder="Image title" />
              </div>
              <div class="form-control">
                <label class="label pb-1">
                  <span class="label-text text-xs font-medium uppercase tracking-wide">Description</span>
                </label>
                <.input field={@item_form[:description]} type="textarea" rows="3" placeholder="Caption or description" />
              </div>
              <div class="form-control">
                <label class="label pb-1">
                  <span class="label-text text-xs font-medium uppercase tracking-wide">Image URL</span>
                </label>
                <.input field={@item_form[:original_url]} type="url" placeholder="https://…" />
              </div>
            </div>

            <%!-- Pinned action bar --%>
            <div class="shrink-0 border-t border-base-300 px-5 py-3 flex items-center gap-2">
              <.status_badge status={@selected_item.status} />
              <div class="flex gap-2 flex-1">
                <%!-- Re-download: terminal states or any item with an error --%>
                <button
                  :if={@selected_item.status in ~w(ready failed discarded) or not is_nil(@selected_item.error)}
                  type="button"
                  class="btn btn-ghost btn-sm gap-1"
                  phx-click="redownload_item"
                  phx-value-id={@selected_item.id}
                  phx-disable-with="…"
                  title="Clear stored images and re-run the full pipeline from download"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Re-download
                </button>

                <%!-- Re-render: terminal states or errored item, with original_image present --%>
                <button
                  :if={(@selected_item.status in ~w(ready failed discarded) or not is_nil(@selected_item.error)) and not is_nil(@selected_item.original_image)}
                  type="button"
                  class="btn btn-ghost btn-sm gap-1"
                  phx-click="rerender_item"
                  phx-value-id={@selected_item.id}
                  phx-disable-with="…"
                  title="Re-run from original downloaded image through the full processing chain"
                >
                  <.icon name="hero-paint-brush" class="size-4" /> Re-render
                </button>
              </div>

              <button type="button" class="btn btn-ghost btn-sm" phx-click="close_item">Cancel</button>
              <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Saving…">Save</button>
            </div>
          </.form>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_item"></div>
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
    item_id = item.id

    socket =
      case socket.assigns.selected_item do
        %{id: ^item_id} -> assign(socket, :selected_item, item)
        _ -> socket
      end

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

  def handle_event("select_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)
    form = Catalog.change_item(item) |> to_form()
    {:noreply, socket |> assign(:selected_item, item) |> assign(:item_form, form)}
  end

  def handle_event("close_item", _, socket) do
    {:noreply, socket |> assign(:selected_item, nil) |> assign(:item_form, nil)}
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
        {:noreply,
         socket
         |> stream_insert(:items, item)
         |> assign(:selected_item, nil)
         |> assign(:item_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset))}
    end
  end

  def handle_event("redownload_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)
    # Clear stored images so DownloadImageWorker fetches fresh copies,
    # then let the worker chain run to ready automatically.
    {:ok, item} = Catalog.update_item_storage(item, %{original_image: nil, processed_image: nil, final_image: nil})
    {:ok, item} = Catalog.update_item_status(item, "pending", error: nil)
    %{item_id: item.id} |> DownloadImageWorker.new() |> Oban.insert()
    source = Catalog.get_source!(socket.assigns.source.id)

    {:noreply,
     socket
     |> assign(:selected_item, item)
     |> assign_source_stats(source)
     |> put_flash(:info, "Re-downloading item")}
  end

  def handle_event("rerender_item", %{"id" => id}, socket) do
    item = Catalog.get_item!(id)

    # Clear rendered output AND color analysis results. If this re-render gets stuck
    # in color_analysis state, the retry dispatch checks `text_color: nil` to decide
    # whether to enqueue ColorAnalysisWorker. Leaving stale text_color would cause
    # retry to misroute to RenderWorker instead.
    # Note: Item.color_changeset/2 validates all three fields as required, so we use
    # a direct Ecto.Changeset.change to clear them.
    {:ok, item} =
      item
      |> Ecto.Changeset.change(%{
        processed_image: nil,
        final_image: nil,
        text_color: nil,
        bg_color: nil,
        bg_opacity: nil
      })
      |> ScientiaCognita.Repo.update()

    {:ok, item} = Catalog.update_item_status(item, "processing", error: nil)
    # ProcessImageWorker reads original_image, then chains color_analysis → render → ready
    %{item_id: item.id} |> ProcessImageWorker.new() |> Oban.insert()

    {:noreply,
     socket
     |> assign_source_stats(Catalog.get_source!(socket.assigns.source.id))
     |> assign(:selected_item, item)
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

  def handle_event("retry_discarded_items", _, socket) do
    source = socket.assigns.source

    items_to_retry =
      Catalog.list_items_by_source(source)
      |> Enum.filter(&(&1.status == "discarded"))

    Enum.each(items_to_retry, fn item ->
      {status, worker} =
        cond do
          is_nil(item.original_image) -> {"pending", DownloadImageWorker}
          is_nil(item.processed_image) -> {"processing", ProcessImageWorker}
          is_nil(item.text_color) -> {"color_analysis", ColorAnalysisWorker}
          true -> {"render", RenderWorker}
        end

      {:ok, _} = Catalog.update_item_status(item, status, error: nil)
      %{item_id: item.id} |> worker.new() |> Oban.insert()
    end)

    {:noreply,
     socket
     |> assign_source_stats(Catalog.get_source!(source.id))
     |> put_flash(:info, "Retrying #{length(items_to_retry)} discarded items")}
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
          is_nil(item.original_image) -> {"pending", DownloadImageWorker}
          is_nil(item.processed_image) -> {"processing", ProcessImageWorker}
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
    |> assign(:discarded_count, status_counts["discarded"] || 0)
    |> assign(:stuck_ids, stuck_ids)
  end

  defp progress_pct(0, _), do: 0
  defp progress_pct(ready, total), do: Float.round(ready / total * 100, 1)

  defp sorted_status_counts(counts) do
    order = ~w(pending downloading processing color_analysis render ready failed discarded)
    Enum.sort_by(counts, fn {status, _} -> Enum.find_index(order, &(&1 == status)) || 99 end)
  end

  # Returns :shimmer | :icon | :render | :image
  # Rules are strict top-down first-match (like function clauses).
  defp thumb_type(%{status: s}) when s in ~w(pending downloading), do: :shimmer
  defp thumb_type(%{status: s, original_image: nil}) when s in ~w(failed discarded), do: :icon
  defp thumb_type(%{status: s}) when s in ~w(failed discarded), do: :image
  defp thumb_type(%{status: "render"}), do: :render
  defp thumb_type(%{final_image: fi}) when not is_nil(fi), do: :image
  defp thumb_type(%{processed_image: pi}) when not is_nil(pi), do: :image
  defp thumb_type(%{original_image: oi}) when not is_nil(oi), do: :image
  defp thumb_type(_), do: :shimmer

  # Returns the URL string to display for :image type thumbnails
  defp thumb_url(%{status: s, final_image: fi} = item) when s in ~w(failed discarded) and not is_nil(fi),
    do: ItemImageUploader.url({fi, item})
  defp thumb_url(%{status: s, processed_image: pi} = item) when s in ~w(failed discarded) and not is_nil(pi),
    do: ItemImageUploader.url({pi, item})
  defp thumb_url(%{status: s, original_image: oi} = item) when s in ~w(failed discarded) and not is_nil(oi),
    do: ItemImageUploader.url({oi, item})
  defp thumb_url(%{final_image: fi} = item) when not is_nil(fi),
    do: ItemImageUploader.url({fi, item})
  defp thumb_url(%{processed_image: pi} = item) when not is_nil(pi),
    do: ItemImageUploader.url({pi, item})
  defp thumb_url(%{original_image: oi} = item) when not is_nil(oi),
    do: ItemImageUploader.url({oi, item})
  defp thumb_url(_), do: nil

  defp row_class("pending"), do: "bg-base-200"
  defp row_class("downloading"), do: "bg-base-200"
  defp row_class("processing"), do: "bg-info/10"
  defp row_class("color_analysis"), do: "bg-info/10"
  defp row_class("render"), do: "bg-info/10"
  defp row_class("ready"), do: ""
  defp row_class("failed"), do: "bg-error/10"
  defp row_class("discarded"), do: "bg-warning/10"
  defp row_class(_), do: ""

  defp gemini_page_json(page) do
    # gemini_pages are always Ecto embedded schema structs, but guard defensively.
    # Drop :__meta__ (Ecto metadata) which is not JSON-serializable.
    data = if is_struct(page), do: page |> Map.from_struct() |> Map.delete(:__meta__), else: page

    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(page)
    end
  end

  defp item_thumbnail(assigns) do
    assigns = assign(assigns, :thumb_type, thumb_type(assigns.item))

    ~H"""
    <%= case @thumb_type do %>
    <% :shimmer -> %>
      <div class="skeleton rounded" style="width: 76px; height: 48px;"></div>
    <% :icon -> %>
      <div
        class="flex items-center justify-center bg-base-300 rounded"
        style="width: 76px; height: 48px;"
      >
        <.icon name="hero-photo" class="size-5 text-base-content/30" />
      </div>
    <% :render -> %>
      <div
        class="rounded overflow-hidden ring-2 ring-primary animate-pulse"
        style="width: 76px; height: 48px;"
      >
        <img
          src={thumb_url(@item)}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>
    <% :image -> %>
      <div class="rounded overflow-hidden" style="width: 76px; height: 48px;">
        <img
          src={thumb_url(@item)}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>
    <% end %>
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
  defp status_class("discarded"), do: "badge-warning"
  defp status_class("downloading"), do: "badge-info"
  defp status_class("processing"), do: "badge-info"
  defp status_class("color_analysis"), do: "badge-info"
  defp status_class("render"), do: "badge-info"
  defp status_class("items_loading"), do: "badge-info animate-pulse"
  defp status_class(_), do: "badge-ghost"
end
