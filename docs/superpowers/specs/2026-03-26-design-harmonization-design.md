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
- `lib/scientia_cognita_web/live/page/catalog_show_live.ex` (lightbox title)

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

**Pages updated:** `dashboard_live.ex`, `users_live.ex`, `sources_live.ex`, `source_show_live.ex`, `catalogs_live.ex`, `catalog_show_live.ex`, `page/catalog_show_live.ex`.

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

**Canonical styling:** `p-14`, icon `size-12 text-base-content/25`, title `text-sm font-medium`, subtitle `text-xs text-neutral`. These values are the resolved consensus from the 4 existing variants.

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

**Colour mapping** (covers all status and role values in the codebase):

| Value | DaisyUI class |
|---|---|
| `"pending"` | `badge-primary` |
| `"processing"` | `badge-warning` |
| `"complete"` | `badge-success` |
| `"failed"` / `"error"` | `badge-error` |
| `"user"` | `badge-neutral` |
| `"admin"` | `badge-primary` |
| `"owner"` | `badge-accent` |
| anything else | `badge-neutral` |

**Template:**
```heex
<span class={"badge badge-#{@size} #{status_badge_class(@status)}"}>
  {@status}
</span>
```

`status_badge_class/1` is a private function in `core_components.ex`:
```elixir
defp status_badge_class(status) do
  case status do
    "pending"    -> "badge-primary"
    "processing" -> "badge-warning"
    "complete"   -> "badge-success"
    "failed"     -> "badge-error"
    "error"      -> "badge-error"
    "user"       -> "badge-neutral"
    "admin"      -> "badge-primary"
    "owner"      -> "badge-accent"
    _            -> "badge-neutral"
  end
end
```

**The `animate-pulse` behaviour** currently on `processing` in `sources_live.ex` is preserved: add `animate-pulse` conditionally inside the template:
```heex
<span class={"badge badge-#{@size} #{status_badge_class(@status)} #{if @status == "processing", do: "animate-pulse"}"}>
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

**Problem:** Two near-identical progress bars exist. `source_show_live.ex` uses `bg-primary` (correct design token). `page/catalog_show_live.ex` hero uses `bg-slate-700` for the track and `bg-gradient-to-r from-blue-500 to-blue-400` for the fill — hardcoded colours that bypass the design token system.

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
      class="bg-primary h-1.5 rounded-full transition-all duration-500"
      style={"width: #{trunc(@value / max(@max, 1) * 100)}%"}
    />
  </div>
</div>
```

Note: `style` is used for the dynamic `width` percentage. This is the correct approach for dynamic CSS values in Phoenix LiveView — it does not count as an inline style smell since it carries runtime data that cannot be a Tailwind class.

**Pages updated:** `source_show_live.ex`, `page/catalog_show_live.ex` (also corrects the off-token colours in the hero upload progress bar).

---

## 6. `<.item_card>` Component

**Problem:** The image grid cell is duplicated between the console catalog detail page and the public catalog detail page. Both use `aspect-video bg-base-300` cards with an image and title. The console version shows a hover remove button; the public version shows status badges. The image selection logic (thumbnail vs final image) is duplicated.

**Attrs:**
```elixir
attr :item, :map, required: true
  # Required keys: :title, :thumbnail_image, :final_image, :id
  # Optional keys for show_status: :status, :uploaded_to_google_photos

attr :on_remove, :string, default: nil
  # If set: shows a "Remove" button on hover (console use)

attr :on_click, :string, default: nil
  # If set: the card is clickable and fires this event (public lightbox)

attr :show_status, :boolean, default: false
  # If true: shows failed/uploaded status badges on the image (public use)
```

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
  class={[
    "card bg-base-200 overflow-hidden group",
    @on_click && "cursor-pointer"
  ]}
  phx-click={@on_click}
  phx-value-id={@on_click && @item.id}
>
  <figure class="aspect-video bg-base-300 relative">
    <img
      :if={item_thumb_url(@item)}
      src={item_thumb_url(@item)}
      class={["w-full h-full object-cover", @on_click && "group-hover:scale-105 transition-transform duration-300"]}
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
        phx-value-id={@item.id}
      >
        Remove
      </button>
    </div>

    <%!-- Public: status badges --%>
    <div :if={@show_status && Map.get(@item, :status) == "failed"}
      class="absolute top-1.5 right-1.5 badge badge-error badge-xs">
      ⚠ failed
    </div>
    <div :if={@show_status && Map.get(@item, :uploaded_to_google_photos)}
      class="absolute bottom-1.5 right-1.5 badge badge-success badge-xs">
      ✓
    </div>
  </figure>
  <div class="card-body p-3">
    <p class="text-xs font-medium truncate text-base-content">{@item.title}</p>
  </div>
</div>
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

New tests added to `test/scientia_cognita_web/live/core_components_test.exs`:

```elixir
describe "status_badge_class/1" do
  test "pending → badge-primary"
  test "processing → badge-warning"
  test "complete → badge-success"
  test "failed → badge-error"
  test "user → badge-neutral"
  test "admin → badge-primary"
  test "owner → badge-accent"
  test "unknown → badge-neutral"
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
| `lib/scientia_cognita_web/live/page/catalog_show_live.ex` | `breadcrumb`, `item_card`, `progress_bar`, `font-serif-display` |
| `docs/design-system.md` | Document the 5 new components |

---

## 10. Out of Scope

- Modal wrapper component (`<.modal>`) — modals in this codebase are complex enough (item editor, picker, confirm) that a shared wrapper would either be too restrictive or require complicated slot composition. Leaving for a future iteration.
- `<.collection_card>` for sources/catalogs list rows — sources and catalogs have diverged enough in their data display that a shared card would have more props than it saves. Each stays as inline markup for now.
- Hero banner refactor (`page/catalog_show_live.ex` `hero_banner/1`) — the 6-state Google Photos hero is complex enough to warrant its own dedicated spec. Out of scope here.
- Accessibility improvements (aria-labels, keyboard nav) — separate concern.
