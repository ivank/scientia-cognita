# Design Harmonization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract 5 reusable components and 1 Tailwind utility from 12+ duplicated patterns to make the console and public UI consistent and reduce maintenance cost.

**Architecture:** All new components go into the existing `lib/scientia_cognita_web/components/core_components.ex`. Tests go in the existing `test/scientia_cognita_web/live/core_components_test.exs`. Each component is spec-driven (exact templates are in the spec) — implement TDD: write the test, confirm it fails, add the component, confirm it passes. Migration tasks replace inline patterns one file at a time.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, HEEx templates, Tailwind CSS v4 with `@utility` directive, DaisyUI component classes, ExUnit with `Phoenix.LiveViewTest.render_component/2` for component testing.

**Spec:** `docs/superpowers/specs/2026-03-26-design-harmonization-design.md`

---

## File Structure

| File | Role in this task |
|---|---|
| `assets/css/app.css` | Add `@utility font-serif-display` after line 138 |
| `lib/scientia_cognita_web/components/core_components.ex` | Add 5 new components + `status_badge_class/1` + `item_thumb_url/1` private helpers before the closing `end` at line 576 |
| `test/scientia_cognita_web/live/core_components_test.exs` | Append new `describe` blocks — do NOT modify existing tests |
| `lib/scientia_cognita_web/components/layouts/root.html.heex` | Replace 1 inline serif style (line 40) |
| `lib/scientia_cognita_web/components/layouts/console.html.heex` | Replace 2 inline serif styles (lines 11, 33) |
| `lib/scientia_cognita_web/controllers/page_html/home.html.heex` | Replace 1 inline serif style (line 6) |
| `lib/scientia_cognita_web/live/console/dashboard_live.ex` | `page_header`, serif style |
| `lib/scientia_cognita_web/live/console/users_live.ex` | `page_header`, `status_badge`, serif styles |
| `lib/scientia_cognita_web/live/console/sources_live.ex` | `page_header`, `empty_state`, `status_badge`, serif styles |
| `lib/scientia_cognita_web/live/console/source_show_live.ex` | `page_header`, `status_badge` (size xs), `progress_bar`, serif styles |
| `lib/scientia_cognita_web/live/console/catalogs_live.ex` | `page_header`, `empty_state`, serif styles |
| `lib/scientia_cognita_web/live/console/catalog_show_live.ex` | `page_header`, `empty_state`, `item_card`, serif styles |
| `lib/scientia_cognita_web/live/page/catalog_show_live.ex` | `breadcrumb`, `empty_state`, `item_card` |
| `docs/design-system.md` | Document 5 new components |

---

## Task 1: Add `font-serif-display` Tailwind Utility and Replace All Inline Serif Styles

**Files:**
- Modify: `assets/css/app.css`
- Modify: `lib/scientia_cognita_web/components/layouts/root.html.heex`
- Modify: `lib/scientia_cognita_web/components/layouts/console.html.heex`
- Modify: `lib/scientia_cognita_web/controllers/page_html/home.html.heex`
- Modify: `lib/scientia_cognita_web/live/console/dashboard_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/users_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalogs_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`

- [ ] **Step 1: Add the utility to `assets/css/app.css`**

After the closing `}` of the `[data-theme=dark]` block (currently line 138), append:

```css
@utility font-serif-display {
  font-family: var(--sc-font-serif);
}
```

- [ ] **Step 2: Replace in `root.html.heex` (line 40)**

Before:
```html
<span style="font-family: var(--sc-font-serif);" class="font-normal text-base text-base-content tracking-tight">
```
After:
```html
<span class="font-serif-display font-normal text-base text-base-content tracking-tight">
```

- [ ] **Step 3: Replace in `console.html.heex` (two occurrences)**

Line 11 — before:
```html
<span style="font-family: var(--sc-font-serif);" class="font-normal ml-2 text-base-content">
```
After:
```html
<span class="font-serif-display font-normal ml-2 text-base-content">
```

Lines 32–37 — before (a `<div>` with style on its own line):
```html
<div
  style="font-family: var(--sc-font-serif);"
  class="font-normal text-sm text-base-content leading-tight"
>
```
After:
```html
<div class="font-serif-display font-normal text-sm text-base-content leading-tight">
```

- [ ] **Step 4: Replace in `home.html.heex` (line 6)**

Before:
```html
<h1 style="font-family: var(--sc-font-serif);" class="text-4xl text-base-content tracking-tight mb-3">
```
After:
```html
<h1 class="font-serif-display text-4xl text-base-content tracking-tight mb-3">
```

- [ ] **Step 5: Replace in all 6 console live files**

The pattern is identical in every case: remove `style="font-family: var(--sc-font-serif);"` and prepend `font-serif-display` to the `class` attribute. Files and locations:

- `dashboard_live.ex` line 12 — `<h1 style="..." class="text-xl text-base-content">`
- `users_live.ex` line 19 — h1; line 75 — modal h3
- `sources_live.ex` line 21 — h1; line 106 — modal h3
- `source_show_live.ex` line 31 — h1 (note: also has `flex items-center gap-3`); line 308 — modal h3 (note: has `text-error` not `text-base-content`)
- `catalogs_live.ex` line 19 — h1; line 64 — modal h3
- `catalog_show_live.ex` line 22 — h1; line 92 — modal h3

After for h1s (example):
```html
<h1 class="font-serif-display text-xl text-base-content">
```

After for source_show h1 (preserves flex):
```html
<h1 class="font-serif-display text-xl text-base-content flex items-center gap-3">
```

After for error modal h3 (preserves text-error):
```html
<h3 class="font-serif-display text-lg text-error">Delete source?</h3>
```

- [ ] **Step 6: Run tests**

```bash
mix test
```
Expected: all existing tests pass. There are no new tests for this task.

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css \
  lib/scientia_cognita_web/components/layouts/root.html.heex \
  lib/scientia_cognita_web/components/layouts/console.html.heex \
  lib/scientia_cognita_web/controllers/page_html/home.html.heex \
  lib/scientia_cognita_web/live/console/dashboard_live.ex \
  lib/scientia_cognita_web/live/console/users_live.ex \
  lib/scientia_cognita_web/live/console/sources_live.ex \
  lib/scientia_cognita_web/live/console/source_show_live.ex \
  lib/scientia_cognita_web/live/console/catalogs_live.ex \
  lib/scientia_cognita_web/live/console/catalog_show_live.ex
git commit -m "feat: add font-serif-display utility and replace all inline serif styles"
```

---

## Task 2: Add `<.page_header>` Component (TDD)

**Files:**
- Modify: `test/scientia_cognita_web/live/core_components_test.exs`
- Modify: `lib/scientia_cognita_web/components/core_components.ex`

- [ ] **Step 1: Update test file imports**

In `test/scientia_cognita_web/live/core_components_test.exs`, update the module header to:

```elixir
defmodule ScientiaCognitaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1, page_header: 1]
  # ... existing tests unchanged ...
```

- [ ] **Step 2: Write the failing tests**

Append to `core_components_test.exs` (after the existing `user_initials` describe block):

```elixir
describe "page_header component" do
  test "renders title with serif class" do
    html = render_component(&page_header/1, %{title: "My Page", subtitle: nil, action: []})
    assert html =~ "My Page"
    assert html =~ "font-serif-display"
  end

  test "renders subtitle when provided" do
    html = render_component(&page_header/1, %{title: "My Page", subtitle: "A description", action: []})
    assert html =~ "A description"
    assert html =~ "text-neutral"
  end

  test "omits subtitle paragraph when nil" do
    html = render_component(&page_header/1, %{title: "My Page", subtitle: nil, action: []})
    refute html =~ "text-neutral text-sm"
  end

  test "has mb-6 bottom margin" do
    html = render_component(&page_header/1, %{title: "T", subtitle: nil, action: []})
    assert html =~ "mb-6"
  end
end
```

- [ ] **Step 3: Run tests to confirm failure**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: `** (UndefinedFunctionError) function ScientiaCognitaWeb.CoreComponents.page_header/1 is undefined`

- [ ] **Step 4: Add `<.page_header>` to `core_components.ex`**

Insert before the `translate_error/1` function (around line 549), directly above the `@doc """Translates an error...` docstring:

```elixir
@doc """
Renders a page header with title, optional subtitle, and optional right-aligned action slot.

## Examples

    <.page_header title="Sources" subtitle="Manage content sources" />

    <.page_header title="Catalogs" subtitle="Your collections">
      <:action>
        <button class="btn btn-primary btn-sm">New</button>
      </:action>
    </.page_header>
"""
attr :title, :string, required: true
attr :subtitle, :string, default: nil
slot :action

def page_header(assigns) do
  ~H"""
  <div class="flex items-start justify-between mb-6">
    <div>
      <h1 class="font-serif-display text-xl text-base-content">{@title}</h1>
      <p :if={@subtitle} class="text-neutral text-sm mt-1">{@subtitle}</p>
    </div>
    <div :if={@action != []} class="shrink-0">
      {render_slot(@action)}
    </div>
  </div>
  """
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: all tests pass including the 4 new `page_header` tests.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita_web/components/core_components.ex \
  test/scientia_cognita_web/live/core_components_test.exs
git commit -m "feat: add page_header component"
```

---

## Task 3: Migrate Console Pages to `<.page_header>`

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/dashboard_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/users_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalogs_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`

**Pattern:** Each page currently has `<.breadcrumb>` + a `<div class="flex items-center justify-between">` (or similar) wrapper containing the h1 and subtitle. Replace the heading `<div>` block with `<.page_header>`. Keep `<.breadcrumb>` as-is. The outer `space-y-6` wrapper stays — it handles spacing between breadcrumb and page_header.

- [ ] **Step 1: Migrate `dashboard_live.ex`**

Replace (lines 11–16):
```heex
<div>
  <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
    Dashboard
  </h1>
  <p class="text-neutral text-sm mt-1">Welcome to the Scientia Cognita console.</p>
</div>
```
With:
```heex
<.page_header title="Dashboard" subtitle="Welcome to the Scientia Cognita console." />
```

- [ ] **Step 2: Migrate `users_live.ex`**

Replace (lines 17–24):
```heex
<div class="flex items-center justify-between">
  <div>
    <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
      Users
    </h1>
    <p class="text-neutral text-sm mt-1">{length(@users)} registered accounts</p>
  </div>
</div>
```
With:
```heex
<.page_header title="Users" subtitle={"#{length(@users)} registered accounts"} />
```

- [ ] **Step 3: Migrate `sources_live.ex`**

Replace (lines 19–31):
```heex
<div class="flex items-center justify-between">
  <div>
    <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
      Sources
    </h1>
    <p class="text-neutral text-sm mt-1">
      URLs crawled and extracted by Gemini into individual items
    </p>
  </div>
  <button class="btn btn-primary btn-sm gap-2" phx-click="open_new_modal">
    <.icon name="hero-plus" class="size-4" /> Add Source
  </button>
</div>
```
With:
```heex
<.page_header title="Sources" subtitle="URLs crawled and extracted by Gemini into individual items">
  <:action>
    <button class="btn btn-primary btn-sm gap-2" phx-click="open_new_modal">
      <.icon name="hero-plus" class="size-4" /> Add Source
    </button>
  </:action>
</.page_header>
```

- [ ] **Step 4: Migrate `source_show_live.ex`**

The current header has the status badge embedded in the h1 and a URL below it. After migration, move both below the page_header as a metadata row.

Also delete the `<%!-- Header --%>` comment at line 23 — it will be orphaned after the block is replaced.

Replace (lines 23–62, the comment and entire header div):
```heex
<div class="flex items-start justify-between gap-4">
  <div>
    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Sources", href: ~p"/console/sources"},
      %{label: Source.display_name(@source)}
    ]} />
    <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content flex items-center gap-3">
      {Source.display_name(@source)}
      <.status_badge status={@source.status} />
    </h1>
    <p class="text-sm text-base-content/50 mt-1 font-mono">{@source.url}</p>
  </div>

  <div class="flex gap-2 shrink-0">
    <button :if={@source.status == "failed"} ... >Restart</button>
    <button :if={@retryable_count > 0} ... >Retry</button>
    <button class="btn btn-error btn-sm gap-2" phx-click="confirm_delete">
      <.icon name="hero-trash" class="size-4" /> Delete
    </button>
  </div>
</div>
```
With (breadcrumb moves outside, page_header replaces header div, status + URL go in a sub-row):
```heex
<.breadcrumb items={[
  %{label: "Console", href: ~p"/console"},
  %{label: "Sources", href: ~p"/console/sources"},
  %{label: Source.display_name(@source)}
]} />
<.page_header title={Source.display_name(@source)}>
  <:action>
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
        :if={@retryable_count > 0}
        class="btn btn-warning btn-sm gap-2"
        phx-click="retry_items"
        phx-disable-with="Retrying…"
      >
        <.icon name="hero-arrow-path" class="size-4" /> Retry {@retryable_count} items
      </button>
      <button class="btn btn-error btn-sm gap-2" phx-click="confirm_delete">
        <.icon name="hero-trash" class="size-4" /> Delete
      </button>
    </div>
  </:action>
</.page_header>
<div class="flex items-center gap-2 -mt-4 mb-4">
  <.status_badge status={@source.status} size="xs" />
  <span class="text-sm text-base-content/50 font-mono">{@source.url}</span>
</div>
```

Note: `-mt-4 mb-4` on the metadata row visually closes the gap between page_header's `mb-6` and this row.

Also note: `source_show_live.ex` previously had `<.breadcrumb>` nested inside the header div. After migration, it is a sibling before `<.page_header>`. This means the outer `<div class="space-y-6">` now wraps: breadcrumb → page_header → metadata row → content. The `space-y-6` adds `mt-6` to each sibling after the first.

- [ ] **Step 5: Migrate `catalogs_live.ex`**

Replace (lines 17–27):
```heex
<div class="flex items-center justify-between">
  <div>
    <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
      Catalogs
    </h1>
    <p class="text-neutral text-sm mt-1">Curated collections published to Google Photos</p>
  </div>
  <button class="btn btn-primary gap-2" phx-click="open_new_modal">
    <.icon name="hero-plus" class="size-4" /> New Catalog
  </button>
</div>
```
With:
```heex
<.page_header title="Catalogs" subtitle="Curated collections published to Google Photos">
  <:action>
    <button class="btn btn-primary gap-2" phx-click="open_new_modal">
      <.icon name="hero-plus" class="size-4" /> New Catalog
    </button>
  </:action>
</.page_header>
```

- [ ] **Step 6: Migrate `catalog_show_live.ex`**

The current structure has breadcrumb nested inside the header div (lines 14–37). Extract breadcrumb out, replace the header div with page_header, keep the catalog slug as a separate small metadata element.

Replace (lines 13–37):
```heex
<%!-- Header --%>
<div class="flex items-start justify-between gap-4">
  <div>
    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Catalogs", href: ~p"/console/catalogs"},
      %{label: @catalog.name}
    ]} />
    <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
      {@catalog.name}
    </h1>
    <p :if={@catalog.description} class="text-base-content/60 mt-1">{@catalog.description}</p>
    <p class="font-mono text-xs text-base-content/40 mt-1">/{@catalog.slug}</p>
  </div>
  <div class="flex gap-2 shrink-0">
    <button
      class="btn btn-primary btn-sm gap-2"
      phx-click="open_picker"
      phx-disable-with="Loading…"
    >
      <.icon name="hero-plus" class="size-4" /> Add Items
    </button>
  </div>
</div>
```
With:
```heex
<.breadcrumb items={[
  %{label: "Console", href: ~p"/console"},
  %{label: "Catalogs", href: ~p"/console/catalogs"},
  %{label: @catalog.name}
]} />
<.page_header title={@catalog.name} subtitle={@catalog.description}>
  <:action>
    <button
      class="btn btn-primary btn-sm gap-2"
      phx-click="open_picker"
      phx-disable-with="Loading…"
    >
      <.icon name="hero-plus" class="size-4" /> Add Items
    </button>
  </:action>
</.page_header>
<p class="font-mono text-xs text-base-content/40 -mt-4 mb-4">/{@catalog.slug}</p>
```

- [ ] **Step 7: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/scientia_cognita_web/live/console/dashboard_live.ex \
  lib/scientia_cognita_web/live/console/users_live.ex \
  lib/scientia_cognita_web/live/console/sources_live.ex \
  lib/scientia_cognita_web/live/console/source_show_live.ex \
  lib/scientia_cognita_web/live/console/catalogs_live.ex \
  lib/scientia_cognita_web/live/console/catalog_show_live.ex
git commit -m "feat: migrate console pages to page_header component"
```

---

## Task 4: Add `<.empty_state>` Component (TDD)

**Files:**
- Modify: `test/scientia_cognita_web/live/core_components_test.exs`
- Modify: `lib/scientia_cognita_web/components/core_components.ex`

- [ ] **Step 1: Update test file imports**

Change the import line to include `empty_state: 1`:
```elixir
import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1, page_header: 1, empty_state: 1]
```

- [ ] **Step 2: Write the failing tests**

Append to `core_components_test.exs`:

```elixir
describe "empty_state component" do
  test "renders icon and title" do
    html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: nil, action: []})
    assert html =~ "No items"
    assert html =~ "hero-photo"
    assert html =~ "p-14"
  end

  test "renders subtitle when provided" do
    html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: "Add one.", action: []})
    assert html =~ "Add one."
    assert html =~ "text-neutral"
  end

  test "omits subtitle when nil" do
    html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: nil, action: []})
    refute html =~ "text-xs text-neutral"
  end
end
```

- [ ] **Step 3: Run tests to confirm failure**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: `** (UndefinedFunctionError) function ScientiaCognitaWeb.CoreComponents.empty_state/1 is undefined`

- [ ] **Step 4: Add `<.empty_state>` to `core_components.ex`**

Insert after the `page_header/1` function, before `translate_error/1`:

```elixir
@doc """
Renders an empty-state placeholder card with an icon, title, optional subtitle,
and optional action button.

## Examples

    <.empty_state icon="hero-globe-alt" title="No sources yet" subtitle="Add a URL to begin." />

    <.empty_state icon="hero-photo" title="No items yet">
      <:action>
        <button class="btn btn-primary btn-sm" phx-click="open_picker">Add Items</button>
      </:action>
    </.empty_state>
"""
attr :icon, :string, required: true
attr :title, :string, required: true
attr :subtitle, :string, default: nil
slot :action

def empty_state(assigns) do
  ~H"""
  <div class="border border-base-300 rounded-box p-14 text-center">
    <.icon name={@icon} class="size-12 mx-auto text-base-content/25" />
    <p class="text-sm font-medium text-base-content mt-3">{@title}</p>
    <p :if={@subtitle} class="text-xs text-neutral mt-1">{@subtitle}</p>
    <div :if={@action != []} class="mt-4 flex justify-center">
      {render_slot(@action)}
    </div>
  </div>
  """
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: all tests pass including the 3 new `empty_state` tests.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita_web/components/core_components.ex \
  test/scientia_cognita_web/live/core_components_test.exs
git commit -m "feat: add empty_state component"
```

---

## Task 5: Migrate Pages to `<.empty_state>`

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalogs_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`
- Modify: `lib/scientia_cognita_web/live/page/catalog_show_live.ex`

- [ ] **Step 1: Replace in `sources_live.ex` (lines 33–37)**

Before:
```heex
<div :if={@sources == []} class="card bg-base-200 p-16 text-center">
  <.icon name="hero-globe-alt" class="size-12 mx-auto text-base-content/20" />
  <p class="mt-4 text-base-content/50 text-sm">No sources yet. Add a URL to begin.</p>
</div>
```
After:
```heex
<.empty_state
  :if={@sources == []}
  icon="hero-globe-alt"
  title="No sources yet"
  subtitle="Add a URL to begin."
/>
```

- [ ] **Step 2: Replace in `catalogs_live.ex` (lines 29–32)**

Before:
```heex
<div :if={@catalogs == []} class="card bg-base-200 p-12 text-center">
  <.icon name="hero-rectangle-stack" class="size-12 mx-auto text-base-content/30" />
  <p class="mt-3 text-base-content/50">No catalogs yet.</p>
</div>
```
After:
```heex
<.empty_state :if={@catalogs == []} icon="hero-rectangle-stack" title="No catalogs yet." />
```

- [ ] **Step 3: Replace in `catalog_show_live.ex` (console, lines 40–46)**

Before:
```heex
<div :if={@catalog_items == []} class="card bg-base-200 p-12 text-center">
  <.icon name="hero-photo" class="size-12 mx-auto text-base-content/30" />
  <p class="mt-3 text-base-content/50">No items yet. Add items from a source.</p>
  <button class="btn btn-primary btn-sm mt-4 mx-auto" phx-click="open_picker">
    Add Items
  </button>
</div>
```
After:
```heex
<.empty_state :if={@catalog_items == []} icon="hero-photo" title="No items yet" subtitle="Add items from a source.">
  <:action>
    <button class="btn btn-primary btn-sm" phx-click="open_picker">Add Items</button>
  </:action>
</.empty_state>
```

- [ ] **Step 4: Replace in `page/catalog_show_live.ex` (lines 37–40)**

Before:
```heex
<div :if={@catalog_items == []} class="card bg-base-200 p-16 text-center">
  <.icon name="hero-photo" class="size-16 mx-auto text-base-content/30" />
  <p class="mt-4 text-base-content/50">No items in this catalog yet.</p>
</div>
```
After:
```heex
<.empty_state
  :if={@catalog_items == []}
  icon="hero-photo"
  title="No items in this catalog yet."
/>
```

Note: This normalizes the public empty state's icon from `size-16` to `size-12` and padding from `p-16` to `p-14`. This is an accepted visual normalization documented in the spec.

- [ ] **Step 5: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita_web/live/console/sources_live.ex \
  lib/scientia_cognita_web/live/console/catalogs_live.ex \
  lib/scientia_cognita_web/live/console/catalog_show_live.ex \
  lib/scientia_cognita_web/live/page/catalog_show_live.ex
git commit -m "feat: migrate empty state blocks to empty_state component"
```

---

## Task 6: Add `<.status_badge>` Component (TDD)

**Files:**
- Modify: `test/scientia_cognita_web/live/core_components_test.exs`
- Modify: `lib/scientia_cognita_web/components/core_components.ex`

- [ ] **Step 1: Update test file imports**

Change the import to:
```elixir
import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1, page_header: 1, empty_state: 1, status_badge: 1]
```

- [ ] **Step 2: Write the failing tests**

Append to `core_components_test.exs`:

```elixir
describe "status_badge_class/1 via status_badge component" do
  test "pending → badge-ghost" do
    html = render_component(&status_badge/1, %{status: "pending", size: "sm"})
    assert html =~ "badge-ghost"
  end

  test "fetching → badge-warning animate-pulse" do
    html = render_component(&status_badge/1, %{status: "fetching", size: "sm"})
    assert html =~ "badge-warning"
    assert html =~ "animate-pulse"
  end

  test "extracting → badge-warning animate-pulse" do
    html = render_component(&status_badge/1, %{status: "extracting", size: "sm"})
    assert html =~ "badge-warning"
    assert html =~ "animate-pulse"
  end

  test "items_loading → badge-info animate-pulse" do
    html = render_component(&status_badge/1, %{status: "items_loading", size: "sm"})
    assert html =~ "badge-info"
    assert html =~ "animate-pulse"
  end

  test "done → badge-success" do
    html = render_component(&status_badge/1, %{status: "done", size: "sm"})
    assert html =~ "badge-success"
    refute html =~ "animate-pulse"
  end

  test "ready → badge-success" do
    html = render_component(&status_badge/1, %{status: "ready", size: "sm"})
    assert html =~ "badge-success"
  end

  test "failed → badge-error" do
    html = render_component(&status_badge/1, %{status: "failed", size: "sm"})
    assert html =~ "badge-error"
  end

  test "discarded → badge-warning (no pulse)" do
    html = render_component(&status_badge/1, %{status: "discarded", size: "sm"})
    assert html =~ "badge-warning"
    refute html =~ "animate-pulse"
  end

  test "downloading → badge-info (no pulse)" do
    html = render_component(&status_badge/1, %{status: "downloading", size: "sm"})
    assert html =~ "badge-info"
    refute html =~ "animate-pulse"
  end

  test "thumbnail → badge-info animate-pulse" do
    html = render_component(&status_badge/1, %{status: "thumbnail", size: "sm"})
    assert html =~ "badge-info"
    assert html =~ "animate-pulse"
  end

  test "analyze → badge-info animate-pulse" do
    html = render_component(&status_badge/1, %{status: "analyze", size: "sm"})
    assert html =~ "badge-info"
    assert html =~ "animate-pulse"
  end

  test "resize → badge-info animate-pulse" do
    html = render_component(&status_badge/1, %{status: "resize", size: "sm"})
    assert html =~ "badge-info"
    assert html =~ "animate-pulse"
  end

  test "render → badge-info animate-pulse" do
    html = render_component(&status_badge/1, %{status: "render", size: "sm"})
    assert html =~ "badge-info"
    assert html =~ "animate-pulse"
  end

  test "owner → badge-accent font-semibold" do
    html = render_component(&status_badge/1, %{status: "owner", size: "sm"})
    assert html =~ "badge-accent"
    assert html =~ "font-semibold"
  end

  test "admin → badge-primary" do
    html = render_component(&status_badge/1, %{status: "admin", size: "sm"})
    assert html =~ "badge-primary"
  end

  test "unknown → badge-ghost" do
    html = render_component(&status_badge/1, %{status: "nonexistent_status", size: "sm"})
    assert html =~ "badge-ghost"
  end
end
```

- [ ] **Step 3: Run tests to confirm failure**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: `** (UndefinedFunctionError) function ScientiaCognitaWeb.CoreComponents.status_badge/1 is undefined`

- [ ] **Step 4: Add `<.status_badge>` and `status_badge_class/1` to `core_components.ex`**

Insert after `empty_state/1`, before `translate_error/1`:

```elixir
@doc """
Renders a DaisyUI badge for source statuses and user roles.

## Examples

    <.status_badge status={source.status} />
    <.status_badge status={source.status} size="xs" />
    <.status_badge status={user.role} />
"""
attr :status, :string, required: true
attr :size, :string, default: "sm", values: ~w(xs sm)

def status_badge(assigns) do
  ~H"""
  <span class={"badge badge-#{@size} #{status_badge_class(@status)}"}>
    {@status}
  </span>
  """
end

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

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```
Expected: all 16 new `status_badge` tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/scientia_cognita_web/components/core_components.ex \
  test/scientia_cognita_web/live/core_components_test.exs
git commit -m "feat: add status_badge component and status_badge_class/1"
```

---

## Task 7: Migrate to Shared `<.status_badge>` (Delete Local Private Functions)

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/users_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

**Context:** `sources_live.ex` and `source_show_live.ex` already call `<.status_badge status={...} />` at call sites — but those calls resolve to the local private `defp status_badge/1` function in each file. After deleting those private functions, Phoenix will automatically fall through to the imported `status_badge/1` from `CoreComponents` (imported via `use ScientiaCognitaWeb, :live_view`). The call sites need no changes except in `source_show_live.ex` where `size="xs"` must be added (the local version used `badge-xs` hardcoded; the shared component defaults to `badge-sm`).

`users_live.ex` uses `<.role_badge role={...}>` — a different function name with a different attr name. This call site must be changed to `<.status_badge status={...} />`.

- [ ] **Step 1: Migrate `users_live.ex`**

1a. In the template (line 42), replace:
```heex
<td><.role_badge role={user.role} /></td>
```
With:
```heex
<td><.status_badge status={user.role} /></td>
```

1b. Delete the private functions (lines 163–173):
```elixir
defp role_badge(assigns) do
  ~H"""
  <span class={"badge badge-sm #{role_class(@role)}"}>
    {@role}
  </span>
  """
end

defp role_class("owner"), do: "badge-accent font-semibold"
defp role_class("admin"), do: "badge-primary"
defp role_class(_), do: "badge-ghost"
```
Delete all 11 lines.

- [ ] **Step 2: Migrate `sources_live.ex`**

Delete only the private functions (lines 230–242 — do NOT change the call site at line 52):
```elixir
defp status_badge(assigns) do
  ~H"""
  <span class={"badge badge-sm #{status_class(@status)}"}>{@status}</span>
  """
end

defp status_class("pending"), do: "badge-ghost"
defp status_class("fetching"), do: "badge-warning animate-pulse"
defp status_class("extracting"), do: "badge-warning animate-pulse"
defp status_class("items_loading"), do: "badge-info animate-pulse"
defp status_class("done"), do: "badge-success"
defp status_class("failed"), do: "badge-error"
defp status_class(_), do: "badge-ghost"
```
Delete all 14 lines.

- [ ] **Step 3: Migrate `source_show_live.ex`**

3a. Add `size="xs"` to all 4 call sites. Find every `<.status_badge status={...}` in this file (lines 33, 85, 119, 225) and add `size="xs"`:
```heex
<.status_badge status={@source.status} size="xs" />
<.status_badge status={status} size="xs" />
<.status_badge status={item.status} size="xs" />
<.status_badge status={@selected_item.status} size="xs" />
```

3b. Delete the local private functions (lines 623–642):
```elixir
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
defp status_class("thumbnail"), do: "badge-info animate-pulse"
defp status_class("analyze"), do: "badge-info animate-pulse"
defp status_class("resize"), do: "badge-info animate-pulse"
defp status_class("render"), do: "badge-info animate-pulse"
defp status_class("items_loading"), do: "badge-info animate-pulse"
defp status_class(_), do: "badge-ghost"
```
Delete all 20 lines.

- [ ] **Step 4: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita_web/live/console/users_live.ex \
  lib/scientia_cognita_web/live/console/sources_live.ex \
  lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "feat: migrate to shared status_badge, delete local private badge functions"
```

---

## Task 8: Add `<.progress_bar>` Component and Migrate `source_show_live.ex`

**Files:**
- Modify: `lib/scientia_cognita_web/components/core_components.ex`
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

No new tests: the component has no branching logic to cover beyond what would be rendered.

- [ ] **Step 1: Add `<.progress_bar>` to `core_components.ex`**

Insert after `status_badge/1` and `status_badge_class/1`, before `translate_error/1`:

```elixir
@doc """
Renders a progress bar with optional label and percentage.

## Examples

    <.progress_bar value={@ready_count} max={@total_items} label="Processing items" />
    <.progress_bar value={42} max={100} />
"""
attr :value, :integer, required: true
attr :max, :integer, required: true
attr :label, :string, default: nil

def progress_bar(assigns) do
  ~H"""
  <div>
    <div :if={@label} class="flex justify-between mb-1">
      <span class="text-xs text-neutral">{@label}</span>
      <span class="text-xs text-neutral">{trunc(@value / max(@max, 1) * 100)}%</span>
    </div>
    <div class="w-full bg-base-300 rounded-full h-2 overflow-hidden">
      <div
        class="bg-success h-2 rounded-full transition-all duration-500"
        style={"width: #{trunc(@value / max(@max, 1) * 100)}%"}
      />
    </div>
  </div>
  """
end
```

- [ ] **Step 2: Replace inline progress bar in `source_show_live.ex`**

Find the progress bar block (lines 71–88):
```heex
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
    ...
  </div>
</div>
```

Replace only the progress bar portion (leave the status counts row below it). The new structure wraps both in a `space-y-1` div:
```heex
<%!-- Progress bar --%>
<div :if={@source.total_items > 0} class="space-y-1">
  <.progress_bar
    value={@status_counts["ready"] || 0}
    max={@source.total_items}
    label="Processing items"
  />
  <div class="flex gap-4 text-xs text-base-content/50 mt-1">
    <span :for={{status, count} <- sorted_status_counts(@status_counts)} :if={count > 0}>
      <.status_badge status={status} size="xs" /> {count}
    </span>
  </div>
</div>
```

Note: The old inline bar showed `{@status_counts["ready"] || 0} / {@source.total_items} ready` as separate text. The new `<.progress_bar label="Processing items">` shows `"Processing items"` on the left and `N%` on the right. This is a minor content change (percentage instead of fraction). The status count breakdown below the bar is preserved unchanged.

- [ ] **Step 3: Delete `progress_pct/2` helper from `source_show_live.ex`**

Find and delete lines 527–528:
```elixir
defp progress_pct(0, _), do: 0
defp progress_pct(ready, total), do: Float.round(ready / total * 100, 1)
```

- [ ] **Step 4: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita_web/components/core_components.ex \
  lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "feat: add progress_bar component, replace inline progress bar in source_show"
```

---

## Task 9: Add `<.item_card>` Component and Migrate Catalog Pages

**Files:**
- Modify: `lib/scientia_cognita_web/components/core_components.ex`
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`
- Modify: `lib/scientia_cognita_web/live/page/catalog_show_live.ex`

No new tests: the component's behaviour is validated by the integration context of the pages that use it.

- [ ] **Step 1: Add `<.item_card>` and `item_thumb_url/1` to `core_components.ex`**

Insert after `progress_bar/1`, before `translate_error/1`:

```elixir
@doc """
Renders an image card for a catalog item.

Set `on_remove` (a phx-click event name) for console edit mode, or `on_click`
for public lightbox mode. `failed` and `uploaded` are pre-computed booleans
from the parent (derived from `export_item_statuses`).

## Examples

    <%!-- Console --%>
    <.item_card id={"catalog-item-\#{item.id}"} item={item} on_remove="remove_item" />

    <%!-- Public --%>
    <.item_card
      id={"item-\#{item.id}"}
      item={item}
      on_click="open_lightbox"
      failed={item_failed?(@export_item_statuses, item.id)}
      uploaded={item_uploaded?(@export_item_statuses, item.id)}
    />
"""
attr :item, :map, required: true
attr :id, :string, default: nil
attr :on_remove, :string, default: nil
attr :on_click, :string, default: nil
attr :failed, :boolean, default: false
attr :uploaded, :boolean, default: false

def item_card(assigns) do
  ~H"""
  <div
    id={@id}
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

      <%!-- Public: failed overlay badge --%>
      <div
        :if={@failed}
        class="absolute top-1.5 right-1.5 bg-error text-error-content text-[10px] font-bold px-1.5 py-0.5 rounded"
      >
        ⚠ FAILED
      </div>

      <%!-- Public: uploaded check overlay --%>
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
  """
end

defp item_thumb_url(item) do
  cond do
    item.thumbnail_image -> ScientiaCognita.Uploaders.ItemImageUploader.url({item.thumbnail_image, item})
    item.final_image     -> ScientiaCognita.Uploaders.ItemImageUploader.url({item.final_image, item})
    true                 -> nil
  end
end
```

- [ ] **Step 2: Replace item grid in `catalog_show_live.ex` (console)**

The alias `ItemImageUploader` is defined in `catalog_show_live.ex` but not in `core_components.ex` (where we use the fully-qualified module name). No changes needed to the existing alias in the live file.

Replace the entire items grid block (lines 48–79, the `<div :if={@catalog_items != []}...>` section with the `for` loop):

Before:
```heex
<div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
  <div
    :for={item <- @catalog_items}
    id={"catalog-item-#{item.id}"}
    class="card bg-base-200 overflow-hidden group"
  >
    <figure class="aspect-video bg-base-300 relative">
      <img
        :if={item.thumbnail_image || item.final_image}
        src={
          if item.thumbnail_image,
            do: ItemImageUploader.url({item.thumbnail_image, item}),
            else: ItemImageUploader.url({item.final_image, item})
        }
        class="w-full h-full object-cover"
        loading="lazy"
      />
      <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
        <button
          class="btn btn-error btn-xs"
          phx-click="remove_item"
          phx-value-item-id={item.id}
        >
          Remove
        </button>
      </div>
    </figure>
    <div class="card-body p-3">
      <p class="text-xs font-medium truncate">{item.title}</p>
      <p :if={item.author} class="text-xs text-base-content/50 truncate">{item.author}</p>
    </div>
  </div>
</div>
```
After:
```heex
<div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
  <.item_card
    :for={item <- @catalog_items}
    id={"catalog-item-#{item.id}"}
    item={item}
    on_remove="remove_item"
  />
</div>
```

- [ ] **Step 3: Replace item grid in `page/catalog_show_live.ex`**

Replace the grid block (lines 42–87, the `<div :if={@catalog_items != []}...>` with the `for` loop):

Before:
```heex
<div :if={@catalog_items != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
  <div
    :for={item <- @catalog_items}
    id={"item-#{item.id}"}
    class={[
      "card bg-base-200 overflow-hidden group cursor-pointer",
      item_failed?(@export_item_statuses, item.id) && "ring-2 ring-error"
    ]}
    phx-click="open_lightbox"
    phx-value-item-id={item.id}
  >
    <figure class="aspect-video bg-base-300 relative">
      <img ... />
      <%!-- Failed badge --%>
      <div :if={item_failed?(@export_item_statuses, item.id)} class="...">⚠ FAILED</div>
      <%!-- Uploaded check --%>
      <div :if={item_uploaded?(@export_item_statuses, item.id)} class="...">
        <.icon name="hero-check" class="size-3" />
      </div>
    </figure>
    <div class="card-body p-3">
      <p class="text-xs font-medium truncate">{item.title}</p>
      <p :if={item.author} class="text-xs text-base-content/50 truncate">{item.author}</p>
    </div>
  </div>
</div>
```
After:
```heex
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
```

- [ ] **Step 4: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/scientia_cognita_web/components/core_components.ex \
  lib/scientia_cognita_web/live/console/catalog_show_live.ex \
  lib/scientia_cognita_web/live/page/catalog_show_live.ex
git commit -m "feat: add item_card component, migrate catalog item grids"
```

---

## Task 10: Migrate Public Breadcrumb

**Files:**
- Modify: `lib/scientia_cognita_web/live/page/catalog_show_live.ex`

- [ ] **Step 1: Replace the inline breadcrumb (lines 13–18)**

Before:
```heex
<%!-- Breadcrumb --%>
<div class="flex items-center gap-2 text-sm text-base-content/50">
  <.link navigate={~p"/"} class="hover:text-base-content">Catalogs</.link>
  <.icon name="hero-chevron-right" class="size-3" />
  <span>{@catalog.name}</span>
</div>
```
After:
```heex
<.breadcrumb items={[
  %{label: "Catalogs", href: ~p"/"},
  %{label: @catalog.name}
]} />
```

- [ ] **Step 2: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita_web/live/page/catalog_show_live.ex
git commit -m "feat: adopt breadcrumb component on public catalog page"
```

---

## Task 11: Update `docs/design-system.md`

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 1: Add new components to the Components section**

After the `### <.breadcrumb>` section in `docs/design-system.md`, add documentation for the 5 new components. Follow the same format as existing component docs (attrs table, usage example).

Add:

```markdown
### `<.page_header>`

Console page heading block with serif title, optional subtitle, and optional right-aligned action slot.

```heex
<.page_header title="Sources" subtitle="Manage content sources" />

<.page_header title="Catalogs" subtitle="Your collections">
  <:action>
    <button class="btn btn-primary btn-sm">New</button>
  </:action>
</.page_header>
```

| Attr       | Type    | Default | Notes                            |
| ---------- | ------- | ------- | -------------------------------- |
| `title`    | string  | req.    | Rendered as `font-serif-display text-xl` |
| `subtitle` | string  | nil     | Rendered as `text-neutral text-sm` |
| `:action`  | slot    | —       | Right-aligned; hidden when empty  |

Always has `mb-6` bottom margin. Use in console pages only (public headings use `text-3xl`).

---

### `<.empty_state>`

Centred empty-state placeholder card with icon, title, optional subtitle, and optional CTA action.

```heex
<.empty_state icon="hero-globe-alt" title="No sources yet" subtitle="Add a URL to begin." />

<.empty_state icon="hero-photo" title="No items yet">
  <:action>
    <button class="btn btn-primary btn-sm" phx-click="open_picker">Add Items</button>
  </:action>
</.empty_state>
```

| Attr       | Type   | Default | Notes                       |
| ---------- | ------ | ------- | --------------------------- |
| `icon`     | string | req.    | Heroicon name, e.g. `hero-photo` |
| `title`    | string | req.    | `text-sm font-medium`       |
| `subtitle` | string | nil     | `text-xs text-neutral`      |
| `:action`  | slot   | —       | CTA button; centred, hidden when empty |

Styling: `border border-base-300 rounded-box p-14`, icon `size-12 text-base-content/25`.

---

### `<.status_badge>`

DaisyUI badge for source processing statuses and user roles. Colour mapping consolidates the logic previously duplicated across three files.

```heex
<.status_badge status={source.status} />
<.status_badge status={source.status} size="xs" />
<.status_badge status={user.role} />
```

| Attr     | Type   | Default | Values      |
| -------- | ------ | ------- | ----------- |
| `status` | string | req.    | Any status or role string |
| `size`   | string | `"sm"`  | `"xs"` · `"sm"` |

Colour mapping: `pending` → ghost, `fetching`/`extracting` → warning + pulse, `items_loading`/`thumbnail`/`analyze`/`resize`/`render` → info + pulse, `done`/`ready` → success, `failed` → error, `discarded` → warning, `downloading` → info, `owner` → accent + semibold, `admin` → primary, unknown → ghost.

---

### `<.progress_bar>`

Progress bar using design tokens. Shows optional label and integer percentage.

```heex
<.progress_bar value={@ready_count} max={@total_items} label="Processing items" />
<.progress_bar value={42} max={100} />
```

| Attr    | Type    | Default | Notes               |
| ------- | ------- | ------- | ------------------- |
| `value` | integer | req.    | Current progress    |
| `max`   | integer | req.    | Total (guards div/0) |
| `label` | string  | nil     | Left label text; when provided, shows label + % right |

Fill colour: `bg-success`. Track: `bg-base-300`. Height: `h-2`.

---

### `<.item_card>`

Image card for catalog items. Supports console edit mode (hover remove) and public lightbox mode (clickable + status overlays).

```heex
<%!-- Console --%>
<.item_card id={"catalog-item-#{item.id}"} item={item} on_remove="remove_item" />

<%!-- Public --%>
<.item_card
  id={"item-#{item.id}"}
  item={item}
  on_click="open_lightbox"
  failed={item_failed?(@export_item_statuses, item.id)}
  uploaded={item_uploaded?(@export_item_statuses, item.id)}
/>
```

| Attr        | Type    | Default | Notes                                              |
| ----------- | ------- | ------- | -------------------------------------------------- |
| `item`      | map     | req.    | Must have `:id`, `:title`, `:thumbnail_image`, `:final_image` |
| `id`        | string  | nil     | DOM id; callers provide format (`catalog-item-N` or `item-N`) |
| `on_remove` | string  | nil     | phx-click event name; shows hover remove overlay  |
| `on_click`  | string  | nil     | phx-click event name; makes card clickable        |
| `failed`    | boolean | false   | Adds `ring-2 ring-error`, `opacity-50`, failed badge |
| `uploaded`  | boolean | false   | Shows success check overlay                       |

`failed` and `uploaded` are computed by the parent from `export_item_statuses` — the component has no knowledge of the export/photos subsystem.
```

- [ ] **Step 2: Also update the `font-serif-display` section in the Typography section**

In `docs/design-system.md`, find the "Applying the Serif Font" subsection and update it to document the utility class:

Before:
```markdown
Since `--sc-font-serif` is a CSS custom property (not a Tailwind utility class), use an inline style:

```heex
<h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
  Page Title
</h1>
```
```

After:
```markdown
Use the `font-serif-display` Tailwind utility class:

```heex
<h1 class="font-serif-display text-xl text-base-content">
  Page Title
</h1>
```
```

- [ ] **Step 3: Run tests**

```bash
mix test
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add docs/design-system.md
git commit -m "docs: add new components and font-serif-display utility to design system"
```

---

## Verification

After all tasks are complete, verify visually:

1. Start the dev server: `mix phx.server`
2. Check console pages (`/console`, `/console/sources`, `/console/catalogs`, etc.) — headings should render in serif font, empty states should be consistent.
3. Check the public catalog page — breadcrumb uses `<.breadcrumb>`, empty state uses `<.empty_state>`, item cards render correctly with status overlays.
4. Run full test suite: `mix test` — expected: all tests pass.
