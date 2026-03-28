defmodule ScientiaCognitaWeb.Page.CatalogShowLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :mount_current_scope}

  alias ScientiaCognita.{Catalog, Photos}
  alias ScientiaCognita.Uploaders.ItemImageUploader
  alias ScientiaCognita.Workers.ExportAlbumWorker

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8 space-y-6">
      <.breadcrumb items={[
        %{label: "Catalogs", href: ~p"/"},
        %{label: @catalog.name}
      ]} />

      <%!-- Catalog title --%>
      <div>
        <h1 class="text-3xl font-bold">{@catalog.name}</h1>
        <p :if={@catalog.description} class="text-base-content/60 mt-1">{@catalog.description}</p>
      </div>

      <%!-- Hero Banner --%>
      <.hero_banner
        current_scope={@current_scope}
        export={@export}
        export_item_statuses={@export_item_statuses}
        export_progress={@export_progress}
        export_total={@export_total}
        export_failed_items={@export_failed_items}
        export_new_count={@export_new_count}
        export_delete_error={@export_delete_error}
        catalog_items={@catalog_items}
        token_status={@token_status}
      />

      <%!-- Items grid --%>
      <.empty_state
        :if={@catalog_items == []}
        icon="hero-photo"
        title="No items in this catalog yet."
      />

      <div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        <.item_card
          :for={item <- @catalog_items}
          id={"item-#{item.id}"}
          item={item}
          on_click="open_lightbox"
          failed={item_failed?(@export_item_statuses, item.id)}
          uploaded={item_uploaded?(@export_item_statuses, item.id)}
        />
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
        <figure class="aspect-video bg-base-300 relative overflow-hidden">
          <div
            :if={is_nil(@lightbox_item.thumbnail_image) and is_nil(@lightbox_item.final_image)}
            class="skeleton absolute inset-0 rounded-none"
          >
          </div>
          <img
            :if={@lightbox_item.thumbnail_image}
            src={ItemImageUploader.url({@lightbox_item.thumbnail_image, @lightbox_item})}
            class="absolute inset-0 w-full h-full object-contain"
          />
          <img
            :if={@lightbox_item.final_image}
            src={ItemImageUploader.url({@lightbox_item.final_image, @lightbox_item})}
            class="absolute inset-0 w-full h-full object-contain opacity-0 transition-opacity duration-700"
            onload={"this.classList.add('opacity-100'); var s=document.getElementById('lb-spinner-#{@lightbox_item.id}'); if(s) s.remove();"}
          />
          <div
            :if={@lightbox_item.final_image}
            id={"lb-spinner-#{@lightbox_item.id}"}
            class="absolute bottom-3 left-3 z-10"
          >
            <span class="loading loading-spinner loading-sm text-base-content/50"></span>
          </div>
        </figure>

        <%!-- Upload error banner (if any) --%>
        <div
          :if={item_error(@export_item_statuses, @lightbox_item.id)}
          class="bg-error/20 border-b border-error/30 px-4 py-2 flex items-center gap-2"
        >
          <.icon name="hero-exclamation-triangle" class="size-4 text-error flex-shrink-0" />
          <span class="text-sm text-error">
            Upload failed: {item_error(@export_item_statuses, @lightbox_item.id)}
          </span>
        </div>

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

    <%!-- Delete confirmation modal --%>
    <div :if={@show_delete_confirm} class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg">Delete album from Google Photos?</h3>
        <p class="py-4 text-base-content/70">
          This will permanently delete the album <strong>{@catalog.name}</strong>
          from your Google Photos library. The photos in this catalog will not be affected.
        </p>
        <div class="modal-action">
          <button class="btn btn-ghost" phx-click="cancel_delete_album">Cancel</button>
          <button class="btn btn-error" phx-click="confirm_delete_album">
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_delete_album"></div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Hero Banner Component
  # ---------------------------------------------------------------------------

  defp hero_banner(assigns) do
    ~H"""
    <%= cond do %>
      <% !@current_scope -> %>
        <div class="rounded-xl p-5 bg-slate-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-lock-closed" class="size-6 text-slate-300" />
              </div>
              <div>
                <div class="font-bold text-base">Save to your Google Photos</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  Sign in to save this catalog directly to your Google Photos library.
                </div>
              </div>
            </div>
            <.link href={~p"/users/log-in"} class="btn btn-primary gap-2 shrink-0">
              <.icon name="hero-key" class="size-4" /> Log in to save
            </.link>
          </div>
        </div>

      <% !has_google_token?(@current_scope) -> %>
        <div class="rounded-xl p-5 bg-slate-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-camera" class="size-6 text-amber-400" />
              </div>
              <div>
                <div class="font-bold text-base">Connect Google Photos</div>
                <div class="flex flex-wrap gap-3 mt-1 text-xs text-slate-400">
                  <span class="flex items-center gap-1">
                    <.icon name="hero-folder-plus" class="size-3" /> Create &amp; manage albums
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-arrow-up-tray" class="size-3" /> Upload photos
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-trash" class="size-3" /> Delete app albums
                  </span>
                </div>
              </div>
            </div>
            <.link href={~p"/auth/google"} class="btn btn-warning gap-2 shrink-0">
              <.icon name="hero-link" class="size-4" /> Connect Google Photos
            </.link>
          </div>
        </div>

      <% is_nil(@export) or @export.status == "deleted" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-slate-700 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-cloud" class="size-6 text-blue-400" />
              </div>
              <div>
                <div class="font-bold text-base">Not yet in your library</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  {length(@catalog_items)} photos ready to save
                </div>
                <.token_status_line token_status={@token_status} />
              </div>
            </div>
            <%= if token_needs_reconnect?(@token_status) do %>
              <.link href={~p"/auth/google"} class="btn btn-warning gap-2 shrink-0">
                <.icon name="hero-link" class="size-4" /> Reconnect Google Photos
              </.link>
            <% else %>
              <button
                class="btn btn-primary gap-2 shrink-0"
                phx-click="export_to_google_photos"
                phx-disable-with="Starting…"
              >
                <.icon name="hero-arrow-up-tray" class="size-4" /> Save to Google Photos
              </button>
            <% end %>
          </div>
        </div>

      <% @export.status == "running" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-blue-900 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap mb-4">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-blue-950 flex items-center justify-center flex-shrink-0 animate-pulse">
                <.icon name="hero-clock" class="size-6 text-blue-400" />
              </div>
              <div>
                <div class="font-bold text-base">Uploading to Google Photos…</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  {@export_progress} uploaded
                  <span :if={length(@export_failed_items) > 0} class="text-red-400 ml-2">
                    · {length(@export_failed_items)} failed
                  </span>
                  <span class="ml-2">of {@export_total}</span>
                </div>
              </div>
            </div>
            <button
              class="btn btn-sm btn-ghost gap-2 text-slate-400 hover:text-white border border-slate-600"
              phx-click="cancel_export"
              phx-disable-with="Cancelling…"
            >
              <.icon name="hero-x-mark" class="size-4" /> Cancel
            </button>
          </div>
          <.progress_bar
            value={@export_progress + length(@export_failed_items)}
            max={@export_total}
          />
          <div class="flex justify-between mt-1.5 text-xs text-slate-500">
            <span>0</span>
            <span>{@export_progress} / {@export_total}</span>
            <span>{@export_total}</span>
          </div>
          <.failed_items_list :if={@export_failed_items != []} items={@export_failed_items} />
        </div>

      <% @export.status == "cancelled" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-slate-600 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-x-circle" class="size-6 text-slate-400" />
              </div>
              <div>
                <div class="font-bold text-base">Upload cancelled</div>
                <div class="text-sm text-slate-400 mt-0.5">
                  {uploaded_item_count(@export_item_statuses)} uploaded
                  <span :if={length(@export_failed_items) > 0} class="text-red-400 ml-2">
                    · {length(@export_failed_items)} failed
                  </span>
                </div>
                <.token_status_line token_status={@token_status} />
              </div>
            </div>
            <div class="flex gap-2 flex-wrap shrink-0">
              <%= if token_needs_reconnect?(@token_status) do %>
                <.link href={~p"/auth/google"} class="btn btn-sm btn-warning gap-2">
                  <.icon name="hero-link" class="size-4" /> Reconnect Google Photos
                </.link>
              <% else %>
                <button
                  class="btn btn-sm gap-2 bg-slate-700 border-slate-500 text-white hover:bg-slate-600"
                  phx-click="export_to_google_photos"
                  phx-disable-with="Starting…"
                >
                  <.icon name="hero-arrow-up-tray" class="size-4" /> Resume upload
                </button>
              <% end %>
            </div>
          </div>
          <.failed_items_list :if={@export_failed_items != []} items={@export_failed_items} />
        </div>

      <% @export.status == "deleting" -> %>
        <div class="rounded-xl p-5 bg-slate-900 border border-slate-600 text-white">
          <div class="flex items-center gap-4">
            <div class="w-12 h-12 rounded-xl bg-slate-700 flex items-center justify-center flex-shrink-0 animate-pulse">
              <.icon name="hero-trash" class="size-6 text-slate-400" />
            </div>
            <div>
              <div class="font-bold text-base">Deleting album from Google Photos…</div>
              <div class="text-sm text-slate-400 mt-0.5">
                <span class="loading loading-spinner loading-xs align-middle mr-1"></span>
                This may take a moment.
              </div>
            </div>
          </div>
        </div>

      <% @export.status == "done" -> %>
        <div class="rounded-xl p-5 bg-emerald-950 border border-emerald-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-emerald-900 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-check-circle" class="size-6 text-emerald-400" />
              </div>
              <div>
                <div class="font-bold text-base">In your Google Photos library</div>
                <div class="text-sm text-emerald-400 mt-0.5">
                  {uploaded_item_count(@export_item_statuses)} uploaded
                  <span :if={length(@export_failed_items) > 0} class="text-red-400 ml-2">
                    · {length(@export_failed_items)} failed
                  </span>
                  <span :if={@export_new_count > 0} class="text-slate-400 ml-2">
                    · {@export_new_count} new
                  </span>
                  <a
                    :if={@export.album_url}
                    href={@export.album_url}
                    target="_blank"
                    class="underline ml-1"
                  >
                    View album ↗
                  </a>
                </div>
                <.token_status_line token_status={@token_status} />
              </div>
            </div>
            <div class="flex gap-2 flex-wrap shrink-0">
              <%= if token_needs_reconnect?(@token_status) do %>
                <.link href={~p"/auth/google"} class="btn btn-sm btn-warning gap-2">
                  <.icon name="hero-link" class="size-4" /> Reconnect to sync
                </.link>
              <% else %>
                <button
                  :if={length(@export_failed_items) > 0}
                  class="btn btn-sm gap-2 bg-red-900 border-red-700 text-red-300 hover:bg-red-800"
                  phx-click="retry_failed_items"
                  phx-disable-with="Retrying…"
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                  Retry failed ({length(@export_failed_items)})
                </button>
                <button
                  :if={@export_new_count > 0}
                  class="btn btn-sm gap-2 bg-emerald-900 border-emerald-700 text-emerald-300 hover:bg-emerald-800"
                  phx-click="sync_new_items"
                  phx-disable-with="Syncing…"
                >
                  <.icon name="hero-arrow-up-tray" class="size-4" />
                  Upload {@export_new_count} new
                </button>
                <button
                  :if={length(@export_failed_items) == 0 and @export_new_count == 0}
                  class="btn btn-sm gap-2 bg-emerald-900 border-emerald-700 text-emerald-300 hover:bg-emerald-800"
                  phx-click="export_to_google_photos"
                  phx-disable-with="Syncing…"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Sync new items
                </button>
              <% end %>
              <button
                class="btn btn-sm gap-2 bg-slate-900 border-red-900 text-red-400 hover:bg-red-950"
                phx-click="delete_album"
              >
                <.icon name="hero-trash" class="size-4" /> Delete album
              </button>
            </div>
          </div>
          <%!-- Delete error section --%>
          <div :if={@export_delete_error} class="mt-3 border-t border-white/10 pt-3">
            <div class="flex items-start gap-2 rounded px-3 py-2.5 bg-red-900/40 text-xs">
              <.icon name="hero-exclamation-triangle" class="size-4 text-red-400 shrink-0 mt-0.5" />
              <div class="flex-1 min-w-0">
                <div class="font-medium text-red-200 mb-1">Could not delete album from Google Photos</div>
                <div class="text-red-400/80">{@export_delete_error}</div>
              </div>
              <div class="flex gap-2 shrink-0">
                <button
                  class="btn btn-ghost btn-xs text-red-300 hover:text-white"
                  phx-click="delete_album"
                  title="Try deleting again"
                >
                  Try again
                </button>
                <button
                  class="btn btn-ghost btn-xs text-slate-400 hover:text-white"
                  phx-click="delete_local_only"
                  title="Remove from this app without deleting from Google Photos"
                >
                  Delete local record
                </button>
              </div>
            </div>
          </div>
          <.failed_items_list :if={@export_failed_items != []} items={@export_failed_items} />
        </div>

      <% @export.status == "failed" -> %>
        <div class="rounded-xl p-5 bg-red-950 border border-red-800 text-white">
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-red-900 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-exclamation-triangle" class="size-6 text-red-400" />
              </div>
              <div>
                <div class="font-bold text-base">Upload failed</div>
                <div class="text-sm text-red-400 mt-0.5">
                  <span :if={length(@export_failed_items) > 0}>
                    {length(@export_failed_items)} items failed
                  </span>
                  <span :if={@export.error} class="ml-1 opacity-70">· {@export.error}</span>
                </div>
                <.token_status_line token_status={@token_status} />
              </div>
            </div>
            <div class="flex gap-2 flex-wrap shrink-0">
              <%= if token_needs_reconnect?(@token_status) do %>
                <.link href={~p"/auth/google"} class="btn btn-sm btn-warning gap-2">
                  <.icon name="hero-link" class="size-4" /> Reconnect Google Photos
                </.link>
              <% else %>
                <button
                  :if={length(@export_failed_items) > 0}
                  class="btn btn-sm gap-2 bg-red-900 border-red-700 text-red-300 hover:bg-red-800"
                  phx-click="retry_failed_items"
                  phx-disable-with="Retrying…"
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                  Retry failed ({length(@export_failed_items)})
                </button>
                <button
                  class="btn btn-sm gap-2 bg-red-900 border-red-700 text-red-300 hover:bg-red-800"
                  phx-click="export_to_google_photos"
                  phx-disable-with="Retrying…"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Retry all
                </button>
              <% end %>
            </div>
          </div>
          <.failed_items_list :if={@export_failed_items != []} items={@export_failed_items} />
        </div>

      <% true -> %>
        <%!-- Fallback: shouldn't occur in practice --%>
    <% end %>
    """
  end

  # Renders token status as a small info line (expired / expiring soon / valid).
  # Returns nothing if the token has no expiry data.
  defp token_status_line(%{token_status: :no_token} = assigns), do: ~H""
  defp token_status_line(%{token_status: :no_expiry} = assigns), do: ~H""

  defp token_status_line(assigns) do
    ~H"""
    <%= case @token_status do %>
      <% {:expired, _} -> %>
        <div class="flex items-center gap-1 mt-1 text-xs text-amber-400">
          <.icon name="hero-exclamation-circle" class="size-3" />
          Google token expired — reconnect to upload
        </div>
      <% {:expiring_soon, _, secs} -> %>
        <div class="flex items-center gap-1 mt-1 text-xs text-amber-300">
          <.icon name="hero-clock" class="size-3" />
          Token expires in {format_duration(secs)} — reconnect to stay connected
        </div>
      <% {:valid, _, secs} -> %>
        <div class="flex items-center gap-1 mt-1 text-xs text-slate-500">
          <.icon name="hero-check" class="size-3" />
          Token valid for {format_duration(secs)}
        </div>
    <% end %>
    """
  end

  # Renders a list of failed items (max 10 shown) with per-item retry buttons.
  defp failed_items_list(assigns) do
    ~H"""
    <div class="mt-3 border-t border-white/10 pt-3 space-y-1.5">
      <div class="text-xs font-medium text-slate-400 mb-2">Failed items:</div>
      <div
        :for={item <- Enum.take(@items, 10)}
        class="flex items-center gap-2 rounded px-2 py-1.5 bg-red-900/30 text-xs"
      >
        <.icon name="hero-exclamation-circle" class="size-3.5 text-red-400 shrink-0" />
        <span class="flex-1 min-w-0">
          <span class="font-medium text-red-200 truncate block">{item.title || "Untitled"}</span>
          <span class="text-red-400/80 truncate block">{item.error}</span>
        </span>
        <button
          class="btn btn-ghost btn-xs text-red-300 hover:text-white shrink-0"
          phx-click="retry_item"
          phx-value-item-id={item.id}
          title="Retry this item"
        >
          <.icon name="hero-arrow-path" class="size-3.5" />
        </button>
      </div>
      <div :if={length(@items) > 10} class="text-xs text-slate-500 pl-2">
        and {length(@items) - 10} more…
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    catalog = Catalog.get_catalog_by_slug!(slug)
    items = Catalog.list_catalog_items(catalog)

    {export, export_item_statuses} =
      if socket.assigns.current_scope do
        user = socket.assigns.current_scope.user
        export = Photos.get_export_for_user(user, catalog)
        statuses = if export, do: Photos.list_export_item_statuses(export), else: %{}
        {export, statuses}
      else
        {nil, %{}}
      end

    if socket.assigns.current_scope do
      user = socket.assigns.current_scope.user
      Phoenix.PubSub.subscribe(ScientiaCognita.PubSub, "export:#{catalog.id}:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, catalog.name)
     |> assign(:catalog, catalog)
     |> assign(:catalog_items, items)
     |> assign(:lightbox_item, nil)
     |> assign(:export, export)
     |> assign(:export_item_statuses, export_item_statuses)
     |> assign(:export_failed_items, compute_failed_items(export_item_statuses, items))
     |> assign(:export_new_count, compute_new_item_count(export_item_statuses, items))
     |> assign(:export_progress, 0)
     |> assign(:export_total, length(items))
     |> assign(:export_delete_error, nil)
     |> assign(:show_delete_confirm, false)
     |> assign(:token_status, compute_token_status(socket.assigns.current_scope))}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_lightbox", %{"item-id" => item_id}, socket) do
    case Integer.parse(item_id) do
      {id, ""} ->
        item = Enum.find(socket.assigns.catalog_items, &(&1.id == id))
        {:noreply, assign(socket, :lightbox_item, item)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_item, nil)}
  end

  def handle_event("export_to_google_photos", _params, socket) do
    if is_nil(socket.assigns.current_scope) do
      {:noreply, socket}
    else
      socket |> assign(:export_delete_error, nil) |> do_start_export()
    end
  end

  def handle_event("retry_failed_items", _params, socket) do
    ids = Enum.map(socket.assigns.export_failed_items, & &1.id)
    socket |> assign(:export_delete_error, nil) |> do_start_export(item_ids: ids)
  end

  def handle_event("retry_item", %{"item-id" => item_id_str}, socket) do
    case Integer.parse(item_id_str) do
      {id, ""} ->
        # Remove from list immediately — it'll be re-added via PubSub if it fails again
        updated_failed = Enum.reject(socket.assigns.export_failed_items, &(&1.id == id))

        socket
        |> assign(:export_failed_items, updated_failed)
        |> do_start_export(item_ids: [id])

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("sync_new_items", _params, socket) do
    ids = new_item_ids(socket.assigns.export_item_statuses, socket.assigns.catalog_items)
    socket |> assign(:export_delete_error, nil) |> do_start_export(item_ids: ids)
  end

  def handle_event("cancel_export", _params, socket) do
    export = socket.assigns.export

    if export && export.status == "running" do
      case Photos.cancel_export(export) do
        {:ok, cancelled_export} ->
          {:noreply, assign(socket, :export, cancelled_export)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_album", _params, socket) do
    {:noreply, socket |> assign(:show_delete_confirm, true) |> assign(:export_delete_error, nil)}
  end

  def handle_event("cancel_delete_album", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  def handle_event("confirm_delete_album", _params, socket) do
    export = socket.assigns.export
    scope = socket.assigns.current_scope

    if is_nil(scope) or is_nil(export) do
      {:noreply, assign(socket, :show_delete_confirm, false)}
    else
      user = scope.user

      {:ok, _job} =
        %{photo_export_id: export.id, user_id: user.id}
        |> ScientiaCognita.Workers.DeleteAlbumWorker.new()
        |> Oban.insert()

      {:noreply, assign(socket, :show_delete_confirm, false)}
    end
  end

  def handle_event("delete_local_only", _params, socket) do
    export = socket.assigns.export
    scope = socket.assigns.current_scope

    if is_nil(scope) or is_nil(export) do
      {:noreply, socket}
    else
      case Photos.delete_local_only(export) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:export, nil)
           |> assign(:export_item_statuses, %{})
           |> assign(:export_failed_items, [])
           |> assign(:export_new_count, 0)
           |> assign(:export_delete_error, nil)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove local record. Please try again.")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:export_progress, %{uploaded: n, failed: _f, total: t}}, socket) do
    {:noreply, socket |> assign(:export_progress, n) |> assign(:export_total, t)}
  end

  # Backwards-compatible clause for any broadcasts without a `failed` key
  def handle_info({:export_progress, %{uploaded: n, total: t}}, socket) do
    {:noreply, socket |> assign(:export_progress, n) |> assign(:export_total, t)}
  end

  def handle_info({:export_item_failed, %{item_id: id, title: title, error: error}}, socket) do
    item_detail = %{id: id, title: title, error: error}
    existing = socket.assigns.export_failed_items

    updated =
      if Enum.any?(existing, &(&1.id == id)),
        do: existing,
        else: existing ++ [item_detail]

    {:noreply, assign(socket, :export_failed_items, updated)}
  end

  def handle_info({:export_done, _}, socket) do
    {:noreply, reload_export(socket)}
  end

  def handle_info({:export_failed, _reason}, socket) do
    socket = reload_export(socket)
    {:noreply, put_flash(socket, :error, "Export failed. Check failed items below.")}
  end

  def handle_info({:export_deleting, _}, socket) do
    {:noreply, reload_export(socket)}
  end

  def handle_info({:export_deleted, _}, socket) do
    {:noreply, reload_export(socket)}
  end

  def handle_info({:export_delete_error, reason}, socket) do
    socket = reload_export(socket)
    {:noreply, assign(socket, :export_delete_error, reason)}
  end

  def handle_info({:export_delete_failed, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Could not delete album: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_start_export(socket, opts \\ []) do
    user = socket.assigns.current_scope.user
    catalog = socket.assigns.catalog

    args =
      case Keyword.get(opts, :item_ids) do
        nil -> %{catalog_id: catalog.id, user_id: user.id}
        ids -> %{catalog_id: catalog.id, user_id: user.id, item_ids: ids}
      end

    total =
      case Keyword.get(opts, :item_ids) do
        nil -> length(socket.assigns.catalog_items)
        ids -> length(ids)
      end

    {:ok, _job} = args |> ExportAlbumWorker.new() |> Oban.insert()

    {:noreply,
     socket
     |> assign(:export_progress, 0)
     |> assign(:export_total, total)}
  end

  defp reload_export(socket) do
    user = socket.assigns.current_scope.user
    catalog = socket.assigns.catalog
    items = socket.assigns.catalog_items
    export = Photos.get_export_for_user(user, catalog)
    statuses = if export, do: Photos.list_export_item_statuses(export), else: %{}

    socket
    |> assign(:export, export)
    |> assign(:export_item_statuses, statuses)
    |> assign(:export_failed_items, compute_failed_items(statuses, items))
    |> assign(:export_new_count, compute_new_item_count(statuses, items))
  end

  # ---------------------------------------------------------------------------
  # Token helpers
  # ---------------------------------------------------------------------------

  defp has_google_token?(nil), do: false
  defp has_google_token?(scope), do: not is_nil(scope.user.google_access_token)

  defp compute_token_status(nil), do: :no_token

  defp compute_token_status(scope) do
    case scope.user.google_token_expires_at do
      nil ->
        :no_expiry

      %DateTime{} = expires_at ->
        diff = DateTime.diff(expires_at, DateTime.utc_now(), :second)

        cond do
          diff <= 0 -> {:expired, expires_at}
          diff < 300 -> {:expiring_soon, expires_at, diff}
          true -> {:valid, expires_at, diff}
        end
    end
  end

  defp token_needs_reconnect?({:expired, _}), do: true
  defp token_needs_reconnect?({:expiring_soon, _, _}), do: true
  defp token_needs_reconnect?(_), do: false

  defp format_duration(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86400 -> "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"
      true -> "#{div(seconds, 86400)}d"
    end
  end

  # ---------------------------------------------------------------------------
  # Item status helpers
  # ---------------------------------------------------------------------------

  defp item_failed?(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "failed"} -> true
      _ -> false
    end
  end

  defp item_uploaded?(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "uploaded"} -> true
      _ -> false
    end
  end

  defp item_error(statuses, item_id) do
    case Map.get(statuses, item_id) do
      %{status: "failed", error: error} -> error
      _ -> nil
    end
  end

  # Returns a list of %{id, title, error} for all failed items, for display in the banner.
  defp compute_failed_items(statuses, catalog_items) do
    statuses
    |> Enum.filter(fn {_id, v} -> v.status == "failed" end)
    |> Enum.map(fn {id, v} ->
      item = Enum.find(catalog_items, &(&1.id == id))
      %{id: id, title: item && item.title, error: v.error}
    end)
  end

  # Returns a count of catalog items that have a final_image but no PhotoExportItem record yet.
  defp compute_new_item_count(statuses, catalog_items) do
    known_ids = Map.keys(statuses)
    Enum.count(catalog_items, &(&1.final_image && &1.id not in known_ids))
  end

  # Returns item IDs for items that have never been attempted (no PhotoExportItem record).
  defp new_item_ids(statuses, catalog_items) do
    known_ids = Map.keys(statuses)

    catalog_items
    |> Enum.filter(&(&1.final_image && &1.id not in known_ids))
    |> Enum.map(& &1.id)
  end

  defp uploaded_item_count(statuses) do
    Enum.count(statuses, fn {_id, v} -> v.status == "uploaded" end)
  end
end
