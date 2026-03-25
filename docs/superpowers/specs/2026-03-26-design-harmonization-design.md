# Design Harmonization Spec

**Date:** 2026-03-26
**Status:** Approved

---

## Overview

Extract 5 new reusable components and 1 Tailwind utility from 12+ duplicated patterns scattered across the console and public pages. The goal is to eliminate copy-pasted Tailwind class combinations, make both sides of the UI consistent, and reduce the maintenance cost of future styling changes.

**Scope:** Console pages + public catalog pages (full scope B).

**No new visual designs.** Every component reflects the patterns already in use — this is consolidation, not redesign.

---

## 1. Tailwind Utility: `font-serif-display`

**Problem:** `style="font-family: var(--sc-font-serif);"` appears as an inline style 17+ times across the codebase. Inline styles are not scannable by Tailwind and create a maintenance smell.

**Solution:** Add a single `@utility` declaration to `assets/css/app.css`, after the existing semantic token block:

```css
@utility font-serif-display {
  font-family: var(--sc-font-serif);
}
```

Every `style="font-family: var(--sc-font-serif);"` attribute in every template and layout file is replaced with `class="font-serif-display"` (appended to any existing `class` attribute). Files affected:

- `lib/scientia_cognita_web/components/layouts/root.html.heex` (logo span)
- `lib/scientia_cognita_web/components/layouts/console.html.heex` (mobile navbar + sidebar logo)
- `lib/scientia_cognita_web/controllers/page_html/home.html.heex` (h1)
- `lib/scientia_cognita_web/live/console/dashboard_live.ex` (h1)
- `lib/scientia_cognita_web/live/console/users_live.ex` (h1, modal h3)
- `lib/scientia_cognita_web/live/console/sources_live.ex` (h1, modal h3)
- `lib/scientia_cognita_web/live/console/source_show_live.ex` (h1, modal h3s)
- `lib/scientia_cognita_web/live/console/catalogs_live.ex` (h1, modal h3)
- `lib/scientia_cognita_web/live/console/catalog_show_live.ex` (h1, modal h3s)

---

## 2. `<.page_header>` Component

**Problem:** All 6 console list/detail pages and the public catalog page repeat an identical heading block with slight variations. The pattern cannot be updated in one place.

**Attrs:**
```elixir
attr :title, :string, required: true
attr :subtitle, :string, default: nil
slot :action  # optional — right-aligned button or button group
```

**Template:**
```heex
<div class="flex items-start justify-between mb-6">
  <div>
    <h1 class="font-serif-display text-xl text-base-content">{@title}</h1>
    <p :if={@subtitle} class="text-neutral text-sm mt-1">{@subtitle}</p>
  </div>
  <div :if={@action != []} class="shrink-0">
    {render_slot(@action)}
  </div>
</div>
```

**Usage examples:**
```heex
<%!-- No action --%>
<.page_header title="Dashboard" subtitle="Welcome to the Scientia Cognita console." />

<%!-- With action --%>
<.page_header title="Sources" subtitle="URLs crawled and extracted by Gemini into individual items">
  <:action>
    <button class="btn btn-primary btn-sm gap-2" phx-click="open_new_modal">
      <.icon name="hero-plus" class="size-4" /> Add Source
    </button>
  </:action>
</.page_header>
```

**Pages updated:** `dashboard_live.ex`, `users_live.ex`, `sources_live.ex`, `source_show_live.ex`, `catalogs_live.ex`, `catalog_show_live.ex` (console only).

**Note:** `page/catalog_show_live.ex` is intentionally excluded. The public catalog page uses `<h1 class="text-3xl font-bold">` as its primary heading — a deliberate visual treatment that does not match the console `text-xl` convention. Applying `<.page_header>` there would silently downgrade the public heading size, which contradicts the "no new visual designs" constraint.

**Note:** The `mb-6` bottom margin is baked in because every page uses the same spacing between the header and the content below. Individual pages should remove any existing `space-y-6` or manual margin they currently use for this gap.

---

## 3. `<.empty_state>` Component

**Problem:** 4 empty-state cards exist with inconsistent padding (`p-12` vs `p-16`), icon opacity (`.20` vs `.30`), and spacing (`mt-3` vs `mt-4`).

**Attrs:**
```elixir
attr :icon, :string, required: true   # heroicon name, e.g. "hero-globe-alt"
attr :title, :string, required: true
attr :subtitle, :string, default: nil
slot :action                           # optional CTA button
```

**Template:**
```heex
<div class="border border-base-300 rounded-box p-14 text-center">
  <.icon name={@icon} class="size-12 mx-auto text-base-content/25" />
  <p class="text-sm font-medium text-base-content mt-3">{@title}</p>
  <p :if={@subtitle} class="text-xs text-neutral mt-1">{@subtitle}</p>
  <div :if={@action != []} class="mt-4 flex justify-center">
    {render_slot(@action)}
  </div>
</div>
```

**Canonical styling:** `p-14`, icon `size-12 text-base-content/25`, title `text-sm font-medium`, subtitle `text-xs text-neutral`. These values are the resolved consensus from the 4 existing variants. The public page empty state (`page/catalog_show_live.ex`) currently uses `size-16` for its icon and `p-16` padding — the harmonized component intentionally reduces both to match the console convention. This is an accepted visual normalization.

**Usage examples:**
```heex
<%!-- No action --%>
<.empty_state icon="hero-globe-alt" title="No sources yet" subtitle="Add a URL to begin." />

<%!-- With action --%>
<.empty_state icon="hero-photo" title="No items yet" subtitle="Add items from a source.">
  <:action>
    <button class="btn btn-primary btn-sm" phx-click="open_picker">Add Items</button>
  </:action>
</.empty_state>
```

**Pages updated:** `sources_live.ex`, `catalogs_live.ex`, `catalog_show_live.ex`, `page/catalog_show_live.ex`.

---

## 4. `<.status_badge>` Component

**Problem:** Two parallel implementations exist — `role_class/1` in `users_live.ex` and `status_class/1` in `sources_live.ex` and `source_show_live.ex`. Both are private functions that produce badge classes. They cannot be reused or tested in isolation.

**Attrs:**
```elixir
attr :status, :string, required: true
attr :size, :string, default: "sm", values: ~w(xs sm)
```

**Colour mapping** — consolidated from the existing `status_class/1` and `role_class/1` private functions across `sources_live.ex`, `source_show_live.ex`, and `users_live.ex`. `source_show_live.ex` has a superset of statuses vs `sources_live.ex`: `sources_live.ex` covers `pending`, `fetching`, `extracting`, `items_loading`, `done`, and `failed`; `source_show_live.ex` additionally handles the item-pipeline statuses `discarded`, `downloading`, `thumbnail`, `analyze`, `resize`, `render`, and `ready`. The new unified component covers all values from both files. The `animate-pulse` classes are embedded in the return value of `status_badge_class/1` (not a separate conditional in the template) to keep all status logic in one place.

**Call-site sizes:** `sources_live.ex` uses `badge-sm` (default); `source_show_live.ex` uses `badge-xs`. When replacing the inline badge in each file, pass the appropriate `size` attr:
- `sources_live.ex` → `<.status_badge status={...} />` (default `size="sm"`)
- `source_show_live.ex` → `<.status_badge status={...} size="xs" />`
- `users_live.ex` → `<.status_badge status={...} />` (default `size="sm"`)

Source statuses (unified — `source_show_live.ex` has a superset):

| Value | DaisyUI classes |
|---|---|
| `"pending"` | `badge-ghost` |
| `"fetching"` | `badge-warning animate-pulse` |
| `"extracting"` | `badge-warning animate-pulse` |
| `"items_loading"` | `badge-info animate-pulse` |
| `"done"` | `badge-success` |
| `"ready"` | `badge-success` |
| `"failed"` | `badge-error` |
| `"discarded"` | `badge-warning` |
| `"downloading"` | `badge-info` |
| `"thumbnail"` | `badge-info animate-pulse` |
| `"analyze"` | `badge-info animate-pulse` |
| `"resize"` | `badge-info animate-pulse` |
| `"render"` | `badge-info animate-pulse` |
| anything else | `badge-ghost` |

Role values (from `users_live.ex` `role_class/1`):

| Value | DaisyUI classes |
|---|---|
| `"owner"` | `badge-accent font-semibold` |
| `"admin"` | `badge-primary` |
| anything else | `badge-ghost` |

**Template:**
```heex
<span class={"badge badge-#{@size} #{status_badge_class(@status)}"}>
  {@status}
</span>
```

`status_badge_class/1` is a private function in `core_components.ex`. It returns the full class string including any `animate-pulse`:

```elixir
defp status_badge_class(status) do
  case status do
    # Source statuses
    "pending"       -> "badge-ghost"
    "fetching"      -> "badge-warning animate-pulse"
    "extracting"    -> "badge-warning animate-pulse"
    "items_loading" -> "badge-info animate-pulse"
    "done"          -> "badge-success"
    "ready"         -> "badge-success"
    "failed"        -> "badge-error"
    "discarded"     -> "badge-warning"
    "downloading"   -> "badge-info"
    "thumbnail"     -> "badge-info animate-pulse"
    "analyze"       -> "badge-info animate-pulse"
    "resize"        -> "badge-info animate-pulse"
    "render"        -> "badge-info animate-pulse"
    # Role values
    "owner"         -> "badge-accent font-semibold"
    "admin"         -> "badge-primary"
    # Default
    _               -> "badge-ghost"
  end
end
```

**Tests** (add to `core_components_test.exs`):
```elixir
describe "status_badge_class/1 via status_badge component" do
  # render and check the badge class for each known status
end
```

**Pages updated:** `users_live.ex` (replaces `<.role_badge>`), `sources_live.ex` (replaces inline badge), `source_show_live.ex` (replaces inline badge).

---

## 5. `<.progress_bar>` Component

**Problem:** `source_show_live.ex` has an inline progress bar using `bg-success` (correct design token). The pattern is worth extracting as a reusable component for future use.

**Scope note:** `page/catalog_show_live.ex` also contains a progress bar, but it lives inside `hero_banner/1` which is explicitly out of scope (see Section 10). The `<.progress_bar>` component is applied to `source_show_live.ex` only. The hero banner progress bar's off-token colours (`bg-gradient-to-r from-blue-500 to-blue-400`) will be addressed in the dedicated hero banner spec.

**Attrs:**
```elixir
attr :value, :integer, required: true
attr :max, :integer, required: true
attr :label, :string, default: nil
```

**Template:**
```heex
<div>
  <div :if={@label} class="flex justify-between mb-1">
    <span class="text-xs text-neutral">{@label}</span>
    <span class="text-xs text-neutral">{trunc(@value / max(@max, 1) * 100)}%</span>
  </div>
  <div class="w-full bg-base-300 rounded-full h-1.5 overflow-hidden">
    <div
      class="bg-success h-1.5 rounded-full transition-all duration-500"
      style={"width: #{trunc(@value / max(@max, 1) * 100)}%"}
    />
  </div>
</div>
```

Note: `style` is used for the dynamic `width` percentage. This is the correct approach for dynamic CSS values in Phoenix LiveView — it does not count as an inline style smell since it carries runtime data that cannot be a Tailwind class.

Note: The existing `source_show_live.ex` uses `Float.round(@value / @max * 100, 1)`, which produces decimal percentages (e.g. `33.3`). The new component uses `trunc(@value / max(@max, 1) * 100)`, producing integer percentages (e.g. `33`). This is an intentional simplification — integer percentages are cleaner for UI display and the difference is imperceptible on the bar width itself.

**Pages updated:** `source_show_live.ex` only (see scope note above).

---

## 6. `<.item_card>` Component

**Problem:** The image grid cell is duplicated between the console catalog detail page and the public catalog detail page. Both use `aspect-video bg-base-300` cards with an image and title. The console version shows a hover remove button; the public version shows status badges. The image selection logic (thumbnail vs final image) is duplicated.

**Attrs:**
```elixir
attr :item, :map, required: true
  # Required keys: :title, :thumbnail_image, :final_image, :id
  # Optional key for card body: :author

attr :on_remove, :string, default: nil
  # If set: shows a "Remove" button on hover (console use)
  # Event is fired with phx-value-item-id={@item.id}

attr :on_click, :string, default: nil
  # If set: the card is clickable and fires this event (public lightbox)
  # Event is fired with phx-value-item-id={@item.id}

attr :failed, :boolean, default: false
  # If true: adds ring-2 ring-error on card, opacity-50 on image, failed badge overlay
  # Parent computes this: failed={item_failed?(@export_item_statuses, item.id)}

attr :uploaded, :boolean, default: false
  # If true: shows a success check overlay on the image
  # Parent computes this: uploaded={item_uploaded?(@export_item_statuses, item.id)}
```

`failed` and `uploaded` are passed as computed booleans from the parent. The `export_item_statuses` map stays in the parent template — `<.item_card>` has no knowledge of the export/photos subsystem.

**Private image helper** (extracted from both pages):
```elixir
defp item_thumb_url(item) do
  cond do
    item.thumbnail_image -> ItemImageUploader.url({item.thumbnail_image, item})
    item.final_image     -> ItemImageUploader.url({item.final_image, item})
    true                 -> nil
  end
end
```

**Template:**
```heex
<div
  id={"item-#{@item.id}"}
  class={[
    "card bg-base-200 overflow-hidden group",
    @on_click && "cursor-pointer",
    @failed && "ring-2 ring-error"
  ]}
  phx-click={@on_click}
  phx-value-item-id={@on_click && @item.id}
>
  <figure class="aspect-video bg-base-300 relative">
    <img
      :if={item_thumb_url(@item)}
      src={item_thumb_url(@item)}
      class={[
        "w-full h-full object-cover",
        @on_click && "group-hover:scale-105 transition-transform duration-300",
        @failed && "opacity-50"
      ]}
      loading="lazy"
    />

    <%!-- Console: hover remove overlay --%>
    <div
      :if={@on_remove}
      class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center"
    >
      <button
        class="btn btn-error btn-xs"
        phx-click={@on_remove}
        phx-value-item-id={@item.id}
      >
        Remove
      </button>
    </div>

    <%!-- Public: failed overlay badge (preserves existing visual style) --%>
    <div
      :if={@failed}
      class="absolute top-1.5 right-1.5 bg-error text-error-content text-[10px] font-bold px-1.5 py-0.5 rounded"
    >
      ⚠ FAILED
    </div>

    <%!-- Public: uploaded check overlay (preserves existing visual style) --%>
    <div
      :if={@uploaded}
      class="absolute bottom-1.5 right-1.5 bg-success text-success-content rounded-full w-5 h-5 flex items-center justify-center"
    >
      <.icon name="hero-check" class="size-3" />
    </div>
  </figure>
  <div class="card-body p-3">
    <p class="text-xs font-medium truncate">{@item.title}</p>
    <p :if={@item[:author]} class="text-xs text-base-content/50 truncate">{@item[:author]}</p>
  </div>
</div>
```

Note: `@item[:author]` uses map access syntax to safely handle both structs (where the key exists but may be `nil`) and plain maps.

**Usage examples:**
```heex
<%!-- Console: hover remove --%>
<.item_card item={item} on_remove="remove_item" />

<%!-- Public: clickable lightbox with status overlays --%>
<.item_card
  item={item}
  on_click="open_lightbox"
  failed={item_failed?(@export_item_statuses, item.id)}
  uploaded={item_uploaded?(@export_item_statuses, item.id)}
/>
```

**Pages updated:** `catalog_show_live.ex` (console), `page/catalog_show_live.ex` (public).

---

## 7. Public Breadcrumb Adoption

**Problem:** `lib/scientia_cognita_web/live/page/catalog_show_live.ex` uses an inline breadcrumb with `hero-chevron-right`, while all console pages use `<.breadcrumb>`.

**Change:** Replace the inline breadcrumb block in the public catalog page:

```heex
<%!-- Remove this: --%>
<div class="flex items-center gap-2 text-sm text-base-content/50">
  <.link navigate={~p"/"} class="hover:text-base-content">Catalogs</.link>
  <.icon name="hero-chevron-right" class="size-3" />
  <span>{@catalog.name}</span>
</div>

<%!-- Replace with: --%>
<.breadcrumb items={[
  %{label: "Catalogs", href: ~p"/"},
  %{label: @catalog.name}
]} />
```

The `<.breadcrumb>` component uses `text-primary` for links, which renders correctly in both light (public) and dark (console) themes.

---

## 8. Testing

Tests appended to the existing file `test/scientia_cognita_web/live/core_components_test.exs`:

```elixir
describe "status_badge_class/1" do
  test "pending → badge-ghost"
  test "fetching → badge-warning animate-pulse"
  test "extracting → badge-warning animate-pulse"
  test "items_loading → badge-info animate-pulse"
  test "done → badge-success"
  test "ready → badge-success"
  test "failed → badge-error"
  test "discarded → badge-warning"
  test "downloading → badge-info"
  test "thumbnail → badge-info animate-pulse"
  test "analyze → badge-info animate-pulse"
  test "resize → badge-info animate-pulse"
  test "render → badge-info animate-pulse"
  test "owner → badge-accent font-semibold"
  test "admin → badge-primary"
  test "unknown → badge-ghost"
end
```

Component rendering tests for `page_header` (with and without action slot) and `empty_state` (with and without action slot) are added in the same file using `Phoenix.LiveViewTest.render_component/2`.

---

## 9. Files Modified

| File | Action |
|---|---|
| `assets/css/app.css` | Add `@utility font-serif-display` |
| `lib/scientia_cognita_web/components/core_components.ex` | Add `page_header`, `empty_state`, `status_badge`, `progress_bar`, `item_card` components + `status_badge_class/1` private fn |
| `test/scientia_cognita_web/live/core_components_test.exs` | Add tests for new components |
| `lib/scientia_cognita_web/components/layouts/root.html.heex` | `font-serif-display` utility class |
| `lib/scientia_cognita_web/components/layouts/console.html.heex` | `font-serif-display` utility class |
| `lib/scientia_cognita_web/controllers/page_html/home.html.heex` | `font-serif-display` utility class |
| `lib/scientia_cognita_web/live/console/dashboard_live.ex` | `page_header`, `font-serif-display` |
| `lib/scientia_cognita_web/live/console/users_live.ex` | `page_header`, `status_badge`, `font-serif-display` |
| `lib/scientia_cognita_web/live/console/sources_live.ex` | `page_header`, `empty_state`, `status_badge`, `font-serif-display` |
| `lib/scientia_cognita_web/live/console/source_show_live.ex` | `page_header`, `status_badge`, `progress_bar`, `font-serif-display` |
| `lib/scientia_cognita_web/live/console/catalogs_live.ex` | `page_header`, `empty_state`, `font-serif-display` |
| `lib/scientia_cognita_web/live/console/catalog_show_live.ex` | `page_header`, `empty_state`, `item_card`, `font-serif-display` |
| `lib/scientia_cognita_web/live/page/catalog_show_live.ex` | `breadcrumb`, `empty_state`, `item_card` |
| `docs/design-system.md` | Document the 5 new components |

---

## 10. Out of Scope

- Modal wrapper component (`<.modal>`) — modals in this codebase are complex enough (item editor, picker, confirm) that a shared wrapper would either be too restrictive or require complicated slot composition. Leaving for a future iteration.
- `<.collection_card>` for sources/catalogs list rows — sources and catalogs have diverged enough in their data display that a shared card would have more props than it saves. Each stays as inline markup for now.
- Hero banner refactor (`page/catalog_show_live.ex` `hero_banner/1`) — the 6-state Google Photos hero is complex enough to warrant its own dedicated spec. Out of scope here.
- Accessibility improvements (aria-labels, keyboard nav) — separate concern.
