# Design System

Scientia Cognita uses a unified design system built on DaisyUI (Tailwind v4) with a thin layer of additional CSS custom properties. All tokens live in `assets/css/app.css`.

**Character:** Scientific precision. Pastel clarity. Not a generic SaaS product.

---

## Themes

Two themes are defined — both in `assets/css/app.css` as `@plugin "../vendor/daisyui-theme"` blocks.

| Theme   | Where       | How                                                        |
| ------- | ----------- | ---------------------------------------------------------- |
| `light` | Public side | Default; user can toggle to `dark` via theme toggle        |
| `dark`  | Console     | Always forced — `data-theme="dark"` on `<html>`, no toggle |

The console uses `console_root.html.heex` which sets `data-theme="dark"` statically and has no theme-detection script. The public side uses `root.html.heex` with a localStorage-based toggle.

---

## Color Tokens

All colors use OKLCH for perceptual uniformity. Hue 218 = Arctic Blue, hue 28 = Warm Coral.

### Light Theme

| Token                  | Value                  | Role                          |
| ---------------------- | ---------------------- | ----------------------------- |
| `--color-base-100`     | `oklch(99% 0.003 218)` | Page background               |
| `--color-base-200`     | `oklch(95% 0.009 218)` | Navbar, cards, sidebar        |
| `--color-base-300`     | `oklch(89% 0.014 218)` | Borders, dividers             |
| `--color-base-content` | `oklch(18% 0.02 222)`  | Body text                     |
| `--color-primary`      | `oklch(52% 0.115 218)` | Links, buttons, interactive   |
| `--color-accent`       | `oklch(68% 0.13 28)`   | CTAs, highlights (warm coral) |
| `--color-neutral`      | `oklch(55% 0.025 222)` | Secondary text, metadata      |

### Dark Theme (Console)

| Token                  | Value                  | Role                   |
| ---------------------- | ---------------------- | ---------------------- |
| `--color-base-100`     | `oklch(17% 0.022 222)` | Content area (darkest) |
| `--color-base-200`     | `oklch(21% 0.026 222)` | Sidebar                |
| `--color-base-300`     | `oklch(25% 0.028 222)` | Borders, dividers      |
| `--color-base-content` | `oklch(84% 0.015 218)` | Body text              |
| `--color-primary`      | `oklch(64% 0.115 218)` | Links, buttons         |
| `--color-accent`       | `oklch(72% 0.13 28)`   | CTAs, highlights       |

### Semantic Aliases

Additional tokens not covered by DaisyUI, available in both themes:

```css
--sc-primary-pale   /* light: very light blue tint; dark: very dark blue tint */
--sc-accent-pale    /* light: very light coral tint; dark: very dark coral tint */
```

---

## Typography

### Font Stack

| Variable          | Stack                                      | Use                              |
| ----------------- | ------------------------------------------ | -------------------------------- |
| `--sc-font-serif` | `'DM Serif Display', Georgia, serif`       | Headings, page titles            |
| `--sc-font-sans`  | `'Inter', system-ui, sans-serif`           | Body text, UI labels, navigation |
| `--sc-font-mono`  | `'JetBrains Mono', 'Fira Code', monospace` | IDs, codes, metadata values      |

DM Serif Display and Inter are loaded from Google Fonts (both layout root files). JetBrains Mono uses the fallback stack only.

### Applying the Serif Font

Use the `font-serif-display` Tailwind utility class:

```heex
<h1 class="font-serif-display text-xl text-base-content">
  Page Title
</h1>
```

### Type Scale

| Usage                    | Font  | Size class                                | Weight  |
| ------------------------ | ----- | ----------------------------------------- | ------- |
| Page title               | Serif | `text-xl`                                 | 400     |
| Section heading          | Serif | `text-lg`                                 | 400     |
| Modal title              | Serif | `text-lg`                                 | 400     |
| Body                     | Sans  | `text-sm`                                 | 400     |
| UI label / column header | Sans  | `text-[10px] uppercase tracking-[0.07em]` | 700     |
| Metadata / secondary     | Sans  | `text-xs`                                 | 400–500 |

---

## Shape & Spacing

| Token               | Value             | Applied to             |
| ------------------- | ----------------- | ---------------------- |
| `--radius-selector` | `0.1875rem` (3px) | Badges, tags           |
| `--radius-field`    | `0.25rem` (4px)   | Inputs, buttons        |
| `--radius-box`      | `0.375rem` (6px)  | Cards, modals, drawers |
| `--depth`           | `0`               | No shadow depth        |

Use DaisyUI's `rounded-box` utility to apply `--radius-box` automatically.

---

## Animation

```css
--sc-transition:       150ms ease   /* hover state changes, color transitions */
--sc-transition-slow:  250ms ease   /* panel opens, layout shifts */
```

In Tailwind: `transition-colors duration-[150ms]`. No bounce, no spring.

---

## Components

### `<.avatar>`

Circular initials avatar. Defined in `core_components.ex`.

```heex
<.avatar initials={user_initials(@current_scope.user.email)} />
<.avatar initials={user_initials(@current_scope.user.email)} size="lg" />
```

| Attr       | Values                                  | Default |
| ---------- | --------------------------------------- | ------- |
| `initials` | string (required)                       | —       |
| `size`     | `sm` (28px) · `md` (32px) · `lg` (40px) | `md`    |

Styling: `rounded-full bg-primary text-primary-content font-bold`.

### `user_initials/1`

Derives two uppercase initials from an email address.

```elixir
user_initials("ivan.kerin@example.com")  # → "IK"
user_initials("ivantest@example.com")    # → "IV"
user_initials("a.b.c@example.com")       # → "AB"
```

Algorithm: take the local part (before `@`), split on `.` or `_`, take the first character of each of the first two segments. If only one segment, take the first two characters. Fallback for non-string input: `"??"`.

### `<.breadcrumb>`

Console navigation trail. Defined in `core_components.ex`.

```heex
<.breadcrumb items={[
  %{label: "Console", href: ~p"/console"},
  %{label: "Catalogs", href: ~p"/console/catalogs"},
  %{label: @catalog.name}
]} />
```

Items with an `:href` key render as `<.link>` in `text-primary`. The last item (no `:href`) renders as plain `text-base-content font-semibold`. Separator: `›` in `text-base-300`.

Place above the page `h1` on every console page.

---

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

---

## Public Interface

### Navbar

- Height: `h-12 min-h-0`
- Background: `bg-base-200 border-b border-base-300`
- Left: `apple-touch-icon.png` (size-7, 6px radius) + "Scientia Cognita" in serif font
- Right: `<.theme_toggle />` + avatar dropdown (logged in) or Login/Register buttons (logged out)

### Footer

```
Scientia Cognita — curated image catalogs
```

`bg-base-200 border-t border-base-300 text-base-content/40 text-xs text-center p-4`

---

## Console Interface

### Sidebar

- Width: `w-64`, `bg-base-200 border-r border-base-300`
- Logo: icon + "Scientia Cognita" (serif 14px) + "Console" (9px uppercase)
- Nav: `menu menu-sm` with `hero-*` icons, section labels at 9px uppercase
- Footer: `<.avatar>` + email + role badge + sign out link. **No theme toggle.**

### Page Header Pattern

```heex
<.breadcrumb items={[%{label: "Console", href: ~p"/console"}, %{label: "Page"}]} />
<h1 style="font-family: var(--sc-font-serif);" class="text-xl text-base-content">
  Page
</h1>
<p class="text-neutral text-sm mt-1">Subtitle</p>
```

### Tables

```heex
<div class="border border-base-300 rounded-box overflow-hidden">
  <table class="table w-full">
    <thead>
      <tr class="bg-base-200 border-b border-base-300">
        <th class="text-[10px] uppercase tracking-[0.07em] text-neutral/70 font-bold">Name</th>
      </tr>
    </thead>
    <tbody>
      <tr class="border-b border-base-300 last:border-0 hover:bg-base-200/60 transition-colors duration-[150ms]">
        ...
      </tr>
    </tbody>
  </table>
</div>
```

### Modals

Title uses serif font: `style="font-family: var(--sc-font-serif);" class="text-lg text-base-content"`. Destructive modals keep `text-error` on the title.

---

## Buttons

| Variant        | Class                         | Use                                |
| -------------- | ----------------------------- | ---------------------------------- |
| Primary        | `btn btn-primary`             | Main actions (Save, Create)        |
| Outlined       | `btn btn-outline btn-primary` | Secondary actions                  |
| Ghost          | `btn btn-ghost`               | Tertiary, Cancel                   |
| Danger         | `btn btn-error`               | Destructive — always confirm first |
| Danger outline | `btn btn-outline btn-error`   | Delete in danger zone              |

---

## Badges

| Variant | Class                          | Use                 |
| ------- | ------------------------------ | ------------------- |
| Primary | `badge badge-primary badge-sm` | Counts, tags        |
| Success | `badge badge-success badge-sm` | Synced, active      |
| Error   | `badge badge-error badge-sm`   | Failed states       |
| Warning | `badge badge-warning badge-sm` | Pending, processing |
| Accent  | `badge badge-accent badge-xs`  | Owner role          |
