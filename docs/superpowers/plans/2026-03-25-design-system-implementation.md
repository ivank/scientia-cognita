# Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Scientia Cognita design system — Arctic Blue + Warm Coral pastel tokens, DM Serif Display typography, unified public navbar with initials avatar, always-dark console with consistent breadcrumbs/tables, and removal of all Phoenix framework references.

**Architecture:** Design tokens live entirely in `assets/css/app.css` as DaisyUI theme plugin blocks plus a `[data-theme]` semantic alias section. Two new Phoenix components (`<.avatar>` and `<.breadcrumb>`) are added to `core_components.ex`. All console pages gain a `<.breadcrumb>` and their existing ad-hoc breadcrumb markup is replaced.

**Tech Stack:** Phoenix LiveView 1.1, Tailwind v4, DaisyUI (local vendor JS), Heroicons v2.2, Elixir/ExUnit for component tests.

---

## File Map

| File | Action |
|---|---|
| `assets/css/app.css` | Replace both daisyUI-theme blocks; add semantic token section |
| `assets/js/app.js` | Update topbar color |
| `lib/scientia_cognita_web/components/layouts/root.html.heex` | Google Fonts; new navbar (avatar); remove Phoenix links |
| `lib/scientia_cognita_web/components/layouts/console_root.html.heex` | Google Fonts; `data-theme="dark"` on `<html>`; remove theme script |
| `lib/scientia_cognita_web/components/layouts/console.html.heex` | Remove `<.theme_toggle />`; fix initials to 2 chars; sidebar polish |
| `lib/scientia_cognita_web/components/layouts.ex` | Remove Phoenix links from `app/1`; update footer |
| `lib/scientia_cognita_web/components/core_components.ex` | Add `user_initials/1`, `<.avatar>`, `<.breadcrumb>` |
| `test/scientia_cognita_web/live/core_components_test.exs` | Create — tests for `user_initials/1` and new components |
| `lib/scientia_cognita_web/controllers/page_html/home.html.heex` | Replace Phoenix welcome page |
| `lib/scientia_cognita_web/live/console/dashboard_live.ex` | Breadcrumb + serif heading |
| `lib/scientia_cognita_web/live/console/users_live.ex` | Breadcrumb + table styling |
| `lib/scientia_cognita_web/live/console/sources_live.ex` | Breadcrumb + serif heading |
| `lib/scientia_cognita_web/live/console/source_show_live.ex` | Replace inline breadcrumb with `<.breadcrumb>` |
| `lib/scientia_cognita_web/live/console/catalogs_live.ex` | Breadcrumb + serif heading |
| `lib/scientia_cognita_web/live/console/catalog_show_live.ex` | Replace inline breadcrumb with `<.breadcrumb>` |
| `.gitignore` | Add `.superpowers/` |

---

## Task 1: Replace CSS design tokens

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Replace the entire contents of `assets/css/app.css`**

  Replace the file with the following. All existing `@import`, `@source`, `@plugin`, `@custom-variant`, and `[data-phx-session]` lines are preserved. Only the two `@plugin "../vendor/daisyui-theme"` blocks change, and a new semantic token block is appended.

```css
/* See the Tailwind configuration guide for advanced usage
   https://tailwindcss.com/docs/configuration */

@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/scientia_cognita_web";

/* A Tailwind plugin that makes "hero-#{ICON}" classes available.
   The heroicons installation itself is managed by your mix.exs */
@plugin "../vendor/heroicons";

/* daisyUI Tailwind Plugin. */
@plugin "../vendor/daisyui" {
  themes: false;
}

/* ============================================================
   LIGHT THEME — public side default
   Arctic Blue + Warm Coral pastel palette
   ============================================================ */
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  prefersdark: false;
  color-scheme: "light";

  --color-base-100: oklch(99% 0.003 218);
  --color-base-200: oklch(95% 0.009 218);
  --color-base-300: oklch(89% 0.014 218);
  --color-base-content: oklch(18% 0.02 222);

  --color-primary: oklch(52% 0.115 218);
  --color-primary-content: oklch(99% 0.003 218);
  --color-secondary: oklch(80% 0.08 218);
  --color-secondary-content: oklch(18% 0.02 222);
  --color-accent: oklch(68% 0.13 28);
  --color-accent-content: oklch(99% 0.003 218);
  --color-neutral: oklch(55% 0.025 222);
  --color-neutral-content: oklch(99% 0.003 218);

  --color-info: oklch(60% 0.12 228);
  --color-info-content: oklch(99% 0.003 218);
  --color-success: oklch(58% 0.13 160);
  --color-success-content: oklch(99% 0.003 218);
  --color-warning: oklch(70% 0.15 55);
  --color-warning-content: oklch(15% 0.04 55);
  --color-error: oklch(58% 0.18 18);
  --color-error-content: oklch(99% 0.003 218);

  --radius-selector: 0.1875rem;
  --radius-field: 0.25rem;
  --radius-box: 0.375rem;
  --size-selector: 0.21875rem;
  --size-field: 0.21875rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}

/* ============================================================
   DARK THEME — console (always forced, never user-toggled)
   Cool Slate — base-100=darkest, base-200=sidebar, base-300=borders
   ============================================================ */
@plugin "../vendor/daisyui-theme" {
  name: "dark";
  default: false;
  prefersdark: true;
  color-scheme: "dark";

  --color-base-100: oklch(17% 0.022 222);
  --color-base-200: oklch(21% 0.026 222);
  --color-base-300: oklch(25% 0.028 222);
  --color-base-content: oklch(84% 0.015 218);

  --color-primary: oklch(64% 0.115 218);
  --color-primary-content: oklch(99% 0.003 218);
  --color-secondary: oklch(38% 0.06 222);
  --color-secondary-content: oklch(84% 0.015 218);
  --color-accent: oklch(72% 0.13 28);
  --color-accent-content: oklch(15% 0.04 28);
  --color-neutral: oklch(30% 0.03 222);
  --color-neutral-content: oklch(84% 0.015 218);

  --color-info: oklch(62% 0.12 228);
  --color-info-content: oklch(99% 0.003 218);
  --color-success: oklch(62% 0.13 160);
  --color-success-content: oklch(99% 0.003 218);
  --color-warning: oklch(72% 0.15 55);
  --color-warning-content: oklch(15% 0.04 55);
  --color-error: oklch(60% 0.18 18);
  --color-error-content: oklch(99% 0.003 218);

  --radius-selector: 0.1875rem;
  --radius-field: 0.25rem;
  --radius-box: 0.375rem;
  --size-selector: 0.21875rem;
  --size-field: 0.21875rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}

/* Add variants based on LiveView classes */
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
@custom-variant phx-submit-loading (.phx-submit-loading&, .phx-submit-loading &);
@custom-variant phx-change-loading (.phx-change-loading&, .phx-change-loading &);

/* Use the data attribute for dark mode  */
@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));

/* Make LiveView wrapper divs transparent for layout */
[data-phx-session], [data-phx-teleported-src] { display: contents }

/* ============================================================
   Design System — semantic tokens
   ============================================================ */

[data-theme=light], [data-theme=dark] {
  /* Typography */
  --sc-font-serif: 'DM Serif Display', Georgia, 'Times New Roman', serif;
  --sc-font-sans: 'Inter', system-ui, -apple-system, sans-serif;
  --sc-font-mono: 'JetBrains Mono', 'Fira Code', monospace;

  /* Animation */
  --sc-transition: 150ms ease;
  --sc-transition-slow: 250ms ease;
}

[data-theme=light] {
  --sc-primary-pale: oklch(93% 0.03 218);
  --sc-accent-pale: oklch(95% 0.04 28);
}

[data-theme=dark] {
  --sc-primary-pale: oklch(25% 0.06 218);
  --sc-accent-pale: oklch(28% 0.06 28);
}
```

- [ ] **Step 2: Verify the app compiles**

  Run: `mix assets.build` (or start `mix phx.server` and check no CSS errors in the browser console).
  Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "feat: replace design tokens with Arctic Blue + Warm Coral pastel system"
```

---

## Task 2: Google Fonts and topbar color

**Files:**
- Modify: `assets/js/app.js`
- Modify: `lib/scientia_cognita_web/components/layouts/root.html.heex`
- Modify: `lib/scientia_cognita_web/components/layouts/console_root.html.heex`

- [ ] **Step 1: Update topbar color in `assets/js/app.js`**

  Change line:
  ```js
  topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
  ```
  To:
  ```js
  topbar.config({barColors: {0: "#4d86b8"}, shadowColor: "rgba(0, 0, 0, .2)"})
  ```

- [ ] **Step 2: Add Google Fonts preconnect + stylesheet to `root.html.heex`**

  In `<head>`, immediately before the `<link phx-track-static rel="stylesheet" ...>` line, insert:

  ```html
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Inter:wght@300;400;500;600;700&display=swap">
  ```

- [ ] **Step 3: Add the same Google Fonts to `console_root.html.heex`**

  Same insertion — immediately before the `<link phx-track-static rel="stylesheet" ...>` line.

- [ ] **Step 4: Commit**

```bash
git add assets/js/app.js \
  lib/scientia_cognita_web/components/layouts/root.html.heex \
  lib/scientia_cognita_web/components/layouts/console_root.html.heex
git commit -m "feat: add DM Serif Display + Inter fonts, update topbar color"
```

---

## Task 3: Force dark theme on console root

**Files:**
- Modify: `lib/scientia_cognita_web/components/layouts/console_root.html.heex`

The console must always render in dark theme. This requires (a) setting `data-theme="dark"` as a static attribute on `<html>` and (b) removing the theme-detection `<script>` block that currently reads from `localStorage` and would fight this.

- [ ] **Step 1: Replace `console_root.html.heex` with the following**

```heex
<!DOCTYPE html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="Console · Scientia Cognita" suffix=" · Scientia Cognita">
      {assigns[:page_title]}
    </.live_title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Inter:wght@300;400;500;600;700&display=swap">
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
    </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

  Note: the theme-detection `<script>` block is intentionally absent. The console is always dark.

- [ ] **Step 2: Commit**

```bash
git add lib/scientia_cognita_web/components/layouts/console_root.html.heex
git commit -m "feat: force dark theme on console, remove theme toggle script"
```

---

## Task 4: `user_initials/1` helper and `<.avatar>` component (TDD)

**Files:**
- Create: `test/scientia_cognita_web/live/core_components_test.exs`
- Modify: `lib/scientia_cognita_web/components/core_components.ex`

The `user_initials/1` function derives two uppercase initials from an email address. It is a pure function, so it is ideal to test first.

Algorithm:
1. Take local part of email (before `@`)
2. Split on `.` or `_`
3. Take first char of each segment, up to 2, uppercase
4. If only one segment, take first 2 chars of that segment, uppercase

- [ ] **Step 1: Create the test file**

```elixir
# test/scientia_cognita_web/live/core_components_test.exs
defmodule ScientiaCognitaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1]

  describe "user_initials/1" do
    test "splits on dot — ivan.kerin@example.com → IK" do
      assert user_initials("ivan.kerin@example.com") == "IK"
    end

    test "splits on underscore — ivan_kerin@example.com → IK" do
      assert user_initials("ivan_kerin@example.com") == "IK"
    end

    test "no separator — ivantest@example.com → IV" do
      assert user_initials("ivantest@example.com") == "IV"
    end

    test "three segments — a.b.c@example.com → AB (only first two)" do
      assert user_initials("a.b.c@example.com") == "AB"
    end

    test "single character local part — a@example.com → AA" do
      assert user_initials("a@example.com") == "AA"
    end

    test "uppercases result" do
      assert user_initials("anna.brown@example.com") == "AB"
    end
  end
end
```

- [ ] **Step 2: Run test — expect failure (function not defined)**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```

  Expected: `** (UndefinedFunctionError) function ScientiaCognitaWeb.CoreComponents.user_initials/1 is undefined`

- [ ] **Step 3: Add `user_initials/1` to `core_components.ex`**

  Add this public function anywhere before the private helpers section (e.g. just before the `## JS Commands` section):

```elixir
@doc """
Derives two uppercase initials from a user's email address.

Algorithm:
  1. Take local part (before "@")
  2. Split on "." or "_"
  3. Take first char of each segment, up to 2, uppercase
  4. If single segment, take first 2 chars of that segment, uppercase

## Examples

    iex> user_initials("ivan.kerin@example.com")
    "IK"
    iex> user_initials("ivantest@example.com")
    "IV"
"""
def user_initials(email) when is_binary(email) do
  local = email |> String.split("@") |> List.first() |> String.downcase()
  parts = String.split(local, ~r/[._]/, trim: true)

  initials =
    case parts do
      [single] ->
        single |> String.slice(0, 2) |> String.upcase()

      [first | rest] ->
        (String.first(first) <> String.first(hd(rest))) |> String.upcase()
    end

  initials
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
mix test test/scientia_cognita_web/live/core_components_test.exs
```

  Expected: `5 tests, 0 failures`

- [ ] **Step 5: Add `<.avatar>` component to `core_components.ex`**

  Add after `user_initials/1`:

```elixir
@doc """
Renders a circular initials avatar.

## Attributes

  * `initials` - two-character string (use `user_initials/1`)
  * `size` - "sm" (28px), "md" (32px, default), "lg" (40px)

## Examples

    <.avatar initials={user_initials(@current_scope.user.email)} />
    <.avatar initials={user_initials(@current_scope.user.email)} size="lg" />
"""
attr :initials, :string, required: true
attr :size, :string, default: "md", values: ~w(sm md lg)

def avatar(assigns) do
  ~H"""
  <div class={[
    "rounded-full bg-primary text-primary-content font-bold font-sans",
    "flex items-center justify-center shrink-0 select-none",
    @size == "sm" && "w-7 h-7 text-xs",
    @size == "md" && "w-8 h-8 text-sm",
    @size == "lg" && "w-10 h-10 text-base"
  ]}>
    {@initials}
  </div>
  """
end
```

- [ ] **Step 6: Add `<.breadcrumb>` component to `core_components.ex`**

  Add after `<.avatar>`. Note: `<:for>` is not valid HEEx slot syntax — use `<%= for %>` with pre-computed `indexed_items` in the function head:

```elixir
@doc """
Renders a breadcrumb trail for console pages.

Items is a list of maps. Items with an `:href` key are rendered as links;
the last item (no `:href`) is rendered as plain text (current page).

## Examples

    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Catalogs", href: ~p"/console/catalogs"},
      %{label: @catalog.name}
    ]} />
"""
attr :items, :list, required: true

def breadcrumb(assigns) do
  indexed = Enum.with_index(assigns.items)
  assigns = assign(assigns, :indexed_items, indexed)

  ~H"""
  <nav class="flex items-center gap-1.5 text-xs mb-2 font-sans">
    <%= for {item, idx} <- @indexed_items do %>
      <span :if={idx > 0} class="text-base-300 select-none">›</span>
      <.link
        :if={Map.has_key?(item, :href)}
        navigate={item.href}
        class="text-primary hover:underline underline-offset-2"
      >
        {item.label}
      </.link>
      <span :if={!Map.has_key?(item, :href)} class="text-base-content font-semibold">
        {item.label}
      </span>
    <% end %>
  </nav>
  """
end
```

- [ ] **Step 7: Commit**

```bash
git add \
  test/scientia_cognita_web/live/core_components_test.exs \
  lib/scientia_cognita_web/components/core_components.ex
git commit -m "feat: add user_initials/1, avatar component, and breadcrumb component"
```

---

## Task 5: Public navbar redesign

**Files:**
- Modify: `lib/scientia_cognita_web/components/layouts/root.html.heex`
- Modify: `lib/scientia_cognita_web/components/layouts.ex`

Two changes: (1) redesign the `<nav>` in `root.html.heex` to use the initials avatar and DM Serif Display title; (2) remove Phoenix framework links from the `app/1` component in `layouts.ex` (that component is used by the Phoenix default home page — it will be replaced in Task 9, but clean the layout now).

  **Import note:** `root.html.heex` and `console.html.heex` can call `user_initials/1` and `<.avatar>` directly because `ScientiaCognitaWeb.Layouts` uses `use ScientiaCognitaWeb, :html`, which imports all of `CoreComponents`. No additional import statement is needed.

- [ ] **Step 1: Replace the `<nav>` block in `root.html.heex`**

  Replace the entire `<nav class="navbar ...">` block (from `<nav` through `</nav>`) with:

```heex
<nav class="navbar bg-base-200 border-b border-base-300 px-4 sm:px-6 h-12 min-h-0">
  <div class="flex-1 flex items-center gap-3">
    <a href="/" class="flex items-center gap-2">
      <img src="/apple-touch-icon.png" class="size-7 rounded-[6px]" />
      <span style="font-family: var(--sc-font-serif);" class="font-normal text-base text-base-content tracking-tight">
        Scientia Cognita
      </span>
    </a>
  </div>
  <div class="flex-none flex items-center gap-2">
    <.theme_toggle />
    <%= if @current_scope do %>
      <div class="dropdown dropdown-end">
        <label tabindex="0" class="cursor-pointer">
          <.avatar initials={user_initials(@current_scope.user.email)} size="sm" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content menu bg-base-200 border border-base-300 rounded-box shadow-lg w-48 p-2 z-50 mt-1"
        >
          <li class="menu-title text-xs truncate px-2 pb-1 text-neutral">
            {@current_scope.user.email}
          </li>
          <li><.link href={~p"/users/settings"}>Settings</.link></li>
          <%= if @current_scope.user.role in ~w(admin owner) do %>
            <li><.link navigate={~p"/console"}>Console</.link></li>
          <% end %>
          <li class="border-t border-base-300 mt-1 pt-1">
            <.link href={~p"/users/log-out"} method="delete" class="text-error">
              Log out
            </.link>
          </li>
        </ul>
      </div>
    <% else %>
      <.link href={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link>
      <.link href={~p"/users/register"} class="btn btn-primary btn-sm">Register</.link>
    <% end %>
  </div>
</nav>
```

- [ ] **Step 2: Remove Phoenix links from `layouts.ex` `app/1` function**

  The `app/1` function in `layouts.ex` is still used by `home.html.heex`. Replace the entire `def app(assigns)` function body with:

```elixir
def app(assigns) do
  ~H"""
  <main class="px-4 py-20 sm:px-6 lg:px-8">
    <div class="mx-auto max-w-2xl space-y-4">
      {render_slot(@inner_block)}
    </div>
  </main>

  <.flash_group flash={@flash} />
  """
end
```

  Also update the `attr` declarations above `def app` — remove the Phoenix-specific ones and keep only `flash` and `current_scope`:

```elixir
attr :flash, :map, required: true, doc: "the map of flash messages"

attr :current_scope, :map,
  default: nil,
  doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

slot :inner_block, required: true
```

- [ ] **Step 3: Commit**

```bash
git add \
  lib/scientia_cognita_web/components/layouts/root.html.heex \
  lib/scientia_cognita_web/components/layouts.ex
git commit -m "feat: redesign public navbar with initials avatar, remove Phoenix links"
```

---

## Task 6: Console sidebar redesign

**Files:**
- Modify: `lib/scientia_cognita_web/components/layouts/console.html.heex`

Changes: remove both `<.theme_toggle />` usages; update the logo section to use DM Serif Display; update sidebar avatar from single char to `user_initials/1`; update active nav item styles.

- [ ] **Step 1: Replace `console.html.heex` with the following**

```heex
<div class="drawer lg:drawer-open min-h-screen bg-base-100">
  <input id="console-drawer" type="checkbox" class="drawer-toggle" />

  <%!-- Main content area --%>
  <div class="drawer-content flex flex-col">
    <%!-- Mobile-only top navbar — no theme toggle --%>
    <div class="navbar bg-base-200 border-b border-base-300 lg:hidden px-4 h-12 min-h-0">
      <label for="console-drawer" class="btn btn-ghost btn-sm">
        <.icon name="hero-bars-3" class="size-5" />
      </label>
      <span style="font-family: var(--sc-font-serif);" class="font-normal ml-2 text-base-content">
        Scientia Cognita
      </span>
    </div>

    <%!-- Page content --%>
    <main class="flex-1 p-6 max-w-7xl mx-auto w-full">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
  </div>

  <%!-- Sidebar --%>
  <div class="drawer-side z-40">
    <label for="console-drawer" aria-label="close sidebar" class="drawer-overlay"></label>

    <aside class="w-64 min-h-full bg-base-200 border-r border-base-300 flex flex-col">
      <%!-- Logo --%>
      <div class="p-4 flex items-center gap-3 border-b border-base-300">
        <img src="/apple-touch-icon.png" class="size-8 rounded-[6px]" />
        <div>
          <div
            style="font-family: var(--sc-font-serif);"
            class="font-normal text-sm text-base-content leading-tight"
          >
            Scientia Cognita
          </div>
          <div class="text-[9px] text-neutral uppercase tracking-widest mt-0.5">Console</div>
        </div>
      </div>

      <%!-- Navigation --%>
      <nav class="flex-1 p-3 space-y-1">
        <ul class="menu menu-sm gap-0.5">
          <li>
            <.link navigate={~p"/console"} class="flex items-center gap-3">
              <.icon name="hero-squares-2x2" class="size-4 shrink-0" /> Dashboard
            </.link>
          </li>
          <li>
            <.link navigate={~p"/console/users"} class="flex items-center gap-3">
              <.icon name="hero-users" class="size-4 shrink-0" /> Users
            </.link>
          </li>
          <li class="menu-title text-[9px] uppercase tracking-widest mt-3 mb-0.5 text-neutral/60">
            Content
          </li>
          <li>
            <.link navigate={~p"/console/sources"} class="flex items-center gap-3">
              <.icon name="hero-globe-alt" class="size-4 shrink-0" /> Sources
            </.link>
          </li>
          <li>
            <.link navigate={~p"/console/catalogs"} class="flex items-center gap-3">
              <.icon name="hero-rectangle-stack" class="size-4 shrink-0" /> Catalogs
            </.link>
          </li>
        </ul>
      </nav>

      <%!-- Bottom: user info + logout — no theme toggle --%>
      <div class="p-3 border-t border-base-300 space-y-2">
        <%= if @current_scope do %>
          <div class="flex items-center gap-2 px-1">
            <.avatar initials={user_initials(@current_scope.user.email)} size="sm" />
            <div class="flex-1 min-w-0">
              <div class="text-xs font-medium truncate text-base-content">
                {@current_scope.user.email}
              </div>
              <span class={"badge badge-xs mt-0.5 #{if @current_scope.user.role == "owner", do: "badge-accent", else: "badge-primary"}"}>
                {@current_scope.user.role}
              </span>
            </div>
          </div>

          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="btn btn-ghost btn-sm w-full justify-start gap-2 text-base-content/60 hover:text-base-content"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
          </.link>
        <% end %>
      </div>
    </aside>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add lib/scientia_cognita_web/components/layouts/console.html.heex
git commit -m "feat: redesign console sidebar — remove theme toggle, fix initials, serif logo"
```

---

## Task 7: Replace Phoenix welcome page

**Files:**
- Modify: `lib/scientia_cognita_web/controllers/page_html/home.html.heex`

Replace the Phoenix default welcome page (which has Phoenix logos, "Peace of mind from prototype to production", and links to phoenixframework.org) with a minimal Scientia Cognita branded landing page.

- [ ] **Step 1: Replace `home.html.heex` with the following**

```heex
<Layouts.flash_group flash={@flash} />

<div class="flex flex-col items-center justify-center min-h-[60vh] px-4 text-center">
  <img src="/apple-touch-icon.png" class="size-16 rounded-xl mb-6 opacity-90" />

  <h1 style="font-family: var(--sc-font-serif);" class="text-4xl text-base-content tracking-tight mb-3">
    Scientia Cognita
  </h1>

  <p class="text-base-content/60 text-sm max-w-sm leading-relaxed mb-8">
    Curated image catalogs. Systematically organized, precisely presented.
  </p>

  <div class="flex items-center gap-3">
    <.link href={~p"/users/log-in"} class="btn btn-primary">
      Sign in
    </.link>
    <.link href={~p"/users/register"} class="btn btn-outline btn-primary">
      Register
    </.link>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add lib/scientia_cognita_web/controllers/page_html/home.html.heex
git commit -m "feat: replace Phoenix welcome page with Scientia Cognita landing"
```

---

## Task 8: Console dashboard — breadcrumb and typography

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/dashboard_live.ex`

- [ ] **Step 1: Update the `render/1` template in `dashboard_live.ex`**

  Replace the opening `<div>` and heading block:

  **Before:**
  ```heex
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold">Dashboard</h1>
      <p class="text-base-content/60 mt-1">Welcome to the Scientia Cognita console.</p>
    </div>
  ```

  **After:**
  ```heex
  <div class="space-y-6">
    <.breadcrumb items={[%{label: "Console"}]} />
    <div>
      <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
        Dashboard
      </h1>
      <p class="text-neutral text-sm mt-1">Welcome to the Scientia Cognita console.</p>
    </div>
  ```

- [ ] **Step 2: Commit**

```bash
git add lib/scientia_cognita_web/live/console/dashboard_live.ex
git commit -m "feat: add breadcrumb and serif heading to console dashboard"
```

---

## Task 9: Console users — breadcrumb and table styling

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/users_live.ex`

- [ ] **Step 1: Update the header section in `users_live.ex`**

  **Before:**
  ```heex
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold">Users</h1>
        <p class="text-base-content/60 mt-1">{length(@users)} registered accounts</p>
      </div>
    </div>
  ```

  **After:**
  ```heex
  <div class="space-y-6">
    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Users"}
    ]} />
    <div class="flex items-center justify-between">
      <div>
        <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
          Users
        </h1>
        <p class="text-neutral text-sm mt-1">{length(@users)} registered accounts</p>
      </div>
    </div>
  ```

- [ ] **Step 2: Update the table container in `users_live.ex`**

  Replace:
  ```heex
  <div class="card bg-base-200">
    <div class="overflow-x-auto">
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>Email</th>
            <th>Role</th>
            <th>Joined</th>
            <th>Confirmed</th>
            <th></th>
          </tr>
        </thead>
  ```

  With:
  ```heex
  <div class="border border-base-300 rounded-box overflow-hidden">
    <div class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr class="bg-base-200 border-b border-base-300">
            <th class="text-[10px] uppercase tracking-[0.07em] text-neutral/70 font-bold">Email</th>
            <th class="text-[10px] uppercase tracking-[0.07em] text-neutral/70 font-bold">Role</th>
            <th class="text-[10px] uppercase tracking-[0.07em] text-neutral/70 font-bold">Joined</th>
            <th class="text-[10px] uppercase tracking-[0.07em] text-neutral/70 font-bold">Confirmed</th>
            <th></th>
          </tr>
        </thead>
  ```

  Also update the table rows to remove `table-zebra` hover and add spec hover:
  ```heex
  <tr :for={user <- @users} id={"user-#{user.id}"}
      class="border-b border-base-300 last:border-0 hover:bg-base-200/60 transition-colors duration-[150ms]">
  ```

- [ ] **Step 3: Update the modal title to serif**

  In the role change modal, replace:
  ```heex
  <h3 class="font-bold text-lg">Change Role</h3>
  ```
  With:
  ```heex
  <h3 style="font-family: var(--sc-font-serif);" class="text-lg text-base-content">Change Role</h3>
  ```

- [ ] **Step 4: Commit**

```bash
git add lib/scientia_cognita_web/live/console/users_live.ex
git commit -m "feat: add breadcrumb, spec table styling to console users page"
```

---

## Task 10: Console sources — breadcrumb and heading

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/sources_live.ex`

- [ ] **Step 1: Update the header block in `sources_live.ex`**

  **Before:**
  ```heex
  <div class="space-y-6">
    <%!-- Page header --%>
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold">Sources</h1>
        <p class="text-base-content/60 mt-1 text-sm">
          URLs crawled and extracted by Gemini into individual items
        </p>
      </div>
      <button class="btn btn-primary btn-sm gap-2" phx-click="open_new_modal">
        <.icon name="hero-plus" class="size-4" /> Add Source
      </button>
    </div>
  ```

  **After:**
  ```heex
  <div class="space-y-6">
    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Sources"}
    ]} />
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

- [ ] **Step 2: Update the modal title**

  Replace:
  ```heex
  <h3 class="font-bold text-lg">Add Source</h3>
  ```
  With:
  ```heex
  <h3 style="font-family: var(--sc-font-serif);" class="text-lg text-base-content">Add Source</h3>
  ```

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita_web/live/console/sources_live.ex
git commit -m "feat: add breadcrumb and serif heading to console sources page"
```

---

## Task 11: Console source detail — replace inline breadcrumb

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/source_show_live.ex`

`source_show_live.ex` has an ad-hoc breadcrumb using `hero-chevron-right`. Replace it with `<.breadcrumb>`.

- [ ] **Step 1: Find and replace the inline breadcrumb block**

  In the `render/1` template, find the block that looks like:
  ```heex
  <div class="flex items-center gap-2 text-sm text-base-content/50 mb-1">
    <.link navigate={~p"/console/sources"} class="hover:text-base-content">Sources</.link>
    <.icon name="hero-chevron-right" class="size-3" />
    <span>{Source.display_name(@source)}</span>
  </div>
  ```

  Replace with:
  ```heex
  <.breadcrumb items={[
    %{label: "Console", href: ~p"/console"},
    %{label: "Sources", href: ~p"/console/sources"},
    %{label: Source.display_name(@source)}
  ]} />
  ```

- [ ] **Step 2: Update the page title `h1`**

  Find:
  ```heex
  <h1 class="text-2xl font-bold">{Source.display_name(@source)}</h1>
  ```
  Replace with:
  ```heex
  <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
    {Source.display_name(@source)}
  </h1>
  ```

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita_web/live/console/source_show_live.ex
git commit -m "feat: replace inline breadcrumb with component in source detail page"
```

---

## Task 12: Console catalogs — breadcrumb and heading

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/catalogs_live.ex`

- [ ] **Step 1: Update the header block in `catalogs_live.ex`**

  **Before:**
  ```heex
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold">Catalogs</h1>
        <p class="text-base-content/60 mt-1">Curated collections published to Google Photos</p>
      </div>
      <button class="btn btn-primary gap-2" phx-click="open_new_modal">
        <.icon name="hero-plus" class="size-4" /> New Catalog
      </button>
    </div>
  ```

  **After:**
  ```heex
  <div class="space-y-6">
    <.breadcrumb items={[
      %{label: "Console", href: ~p"/console"},
      %{label: "Catalogs"}
    ]} />
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

- [ ] **Step 2: Update the modal title**

  Replace:
  ```heex
  <h3 class="font-bold text-lg">New Catalog</h3>
  ```
  With:
  ```heex
  <h3 style="font-family: var(--sc-font-serif);" class="text-lg text-base-content">New Catalog</h3>
  ```

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita_web/live/console/catalogs_live.ex
git commit -m "feat: add breadcrumb and serif heading to console catalogs page"
```

---

## Task 13: Console catalog detail — replace inline breadcrumb

**Files:**
- Modify: `lib/scientia_cognita_web/live/console/catalog_show_live.ex`

- [ ] **Step 1: Replace the inline breadcrumb block**

  In the `render/1` template, find:
  ```heex
  <div class="flex items-center gap-2 text-sm text-base-content/50 mb-1">
    <.link navigate={~p"/console/catalogs"} class="hover:text-base-content">
      Catalogs
    </.link>
    <.icon name="hero-chevron-right" class="size-3" />
    <span>{@catalog.name}</span>
  </div>
  ```

  Replace with:
  ```heex
  <.breadcrumb items={[
    %{label: "Console", href: ~p"/console"},
    %{label: "Catalogs", href: ~p"/console/catalogs"},
    %{label: @catalog.name}
  ]} />
  ```

- [ ] **Step 2: Update the page title `h1`**

  Find:
  ```heex
  <h1 class="text-2xl font-bold">{@catalog.name}</h1>
  ```
  Replace with:
  ```heex
  <h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
    {@catalog.name}
  </h1>
  ```

- [ ] **Step 3: Commit**

```bash
git add lib/scientia_cognita_web/live/console/catalog_show_live.ex
git commit -m "feat: replace inline breadcrumb with component in catalog detail page"
```

---

## Task 14: Add `.superpowers/` to .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add `.superpowers/` to `.gitignore`**

  Append to `.gitignore`:
  ```
  # Visual companion mockups
  .superpowers/
  ```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore .superpowers/ directory"
```

---

## Final Verification

- [ ] Run `mix test` — all tests pass (including the new `core_components_test.exs`)
- [ ] Start `mix phx.server` and verify:
  - Public side renders with light theme, serif title, initials avatar in navbar
  - Console opens in dark theme with no flash, no theme toggle in sidebar
  - Each console page shows the correct breadcrumb trail
  - Navigating back through breadcrumbs works correctly
  - Theme toggle on public side still persists across page reloads
  - Home page shows the new Scientia Cognita landing (no Phoenix logos)
