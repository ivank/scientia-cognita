# Scientia Cognita — Design System Spec

**Date:** 2026-03-24
**Status:** Approved

---

## Overview

A unified design system for Scientia Cognita covering both the public-facing catalog interface and the private admin console. The system is built on top of DaisyUI (Tailwind v4 plugin) using its theme token mechanism, with a thin additional layer of semantic CSS custom properties.

**Design character:** Scientific precision. Pastel clarity. A curated catalog tool — not a generic SaaS product.

---

## 1. Architecture

### Approach

- **Token layer:** Replace the existing DaisyUI theme blocks in `assets/css/app.css` (the `@plugin "../vendor/daisyui-theme"` entries). Two themes: `light` (public default) and `dark` (console, always forced). This keeps DaisyUI components working out of the box.
- **Semantic aliases:** A `[data-theme=light]` + `[data-theme=dark]` `:root` block section within `app.css` defines additional CSS custom properties (e.g. `--sc-primary-pale`) not covered by DaisyUI tokens.
- **No new build tools.** Stays within the existing Tailwind v4 + DaisyUI stack.
- **Intent vs current state:** The existing codebase has working dark/light themes with a teal-blue + orange color scheme. This spec replaces those color values with the new Arctic Blue + Warm Coral pastel palette:
  - Primary: teal-blue hue unchanged (hue ~218), lightness and chroma adjusted to pastel
  - Accent: **hue changes from 48 (orange-yellow) to 28 (warm coral/terracotta)**. This is a deliberate shift — the existing orange reads energetic; the new coral is warmer and softer, fitting the scientific pastel character.
  - Border radii reduced: `--radius-box: 0.75rem` → `0.375rem` (6px)
  - Shadow depth removed: `--depth: 1` → `0`

---

## 2. Color Tokens

All colors use the OKLCH color space for perceptual uniformity.

**DaisyUI dark theme convention:** `base-100` = the darkest surface (card/content area), `base-200` = sidebar/elevated, `base-300` = borders/dividers. This matches DaisyUI's default dark theme convention and the existing codebase pattern.

### 2.1 Public Theme (`light`) — replace existing `light` block

```css
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

  --radius-selector: 0.1875rem;  /* 3px */
  --radius-field: 0.25rem;       /* 4px */
  --radius-box: 0.375rem;        /* 6px — reduced from previous 0.75rem */
  --size-selector: 0.21875rem;
  --size-field: 0.21875rem;
  --border: 1px;
  --depth: 0;                    /* no shadow depth — changed from previous 1 */
  --noise: 0;
}
```

### 2.2 Console Theme (`dark`) — replace existing `dark` block

```css
@plugin "../vendor/daisyui-theme" {
  name: "dark";
  default: false;
  prefersdark: true;
  color-scheme: "dark";

  /* base-100 = darkest (content area), base-200 = sidebar, base-300 = borders */
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
```

### 2.3 Semantic Aliases + Typography + Animation Tokens

All additional tokens are added to `app.css` **after** the two `@plugin "../vendor/daisyui-theme"` blocks, as a single combined block. This preserves all existing `@import`, `@source`, `@plugin`, `@custom-variant`, and `[data-phx-session]` rules — only the theme plugin blocks are replaced; everything else stays.

```css
/* ============================================================
   Design System — semantic tokens (append after daisyui-theme blocks)
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

**Important:** The existing `app.css` contains essential rules that must be kept:
- `@import "tailwindcss" source(none)` and `@source` directives
- `@plugin "../vendor/heroicons"`
- `@plugin "../vendor/daisyui" { themes: false; }`
- `@custom-variant phx-click-loading`, `phx-submit-loading`, `phx-change-loading`
- `@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *))`
- `[data-phx-session], [data-phx-teleported-src] { display: contents }`

Only the two `@plugin "../vendor/daisyui-theme"` blocks are replaced; everything else is preserved.

---

## 3. Shape & Spacing

All radius values are in `rem` (DaisyUI token format):

| Token | Value | Applied to |
|---|---|---|
| `--radius-selector` | `0.1875rem` (3px) | Badges, tags |
| `--radius-field` | `0.25rem` (4px) | Input fields, buttons |
| `--radius-box` | `0.375rem` (6px) | Cards, modals, drawers |
| `--border` | `1px` | All borders |
| `--depth` | `0` | No DaisyUI shadow depth (intentional change from previous `1`) |
| `--noise` | `0` | No texture |

**Philosophy:** "Little round corners" — enough softness to feel modern, not playful. Precise and consistent.

---

## 4. Typography

### Font Stack

| CSS Variable | Value | Role |
|---|---|---|
| `--sc-font-serif` | `'DM Serif Display', Georgia, 'Times New Roman', serif` | Headings, page titles, catalog names |
| `--sc-font-sans` | `'Inter', system-ui, -apple-system, sans-serif` | Body text, UI labels, navigation |
| `--sc-font-mono` | `'JetBrains Mono', 'Fira Code', monospace` | IDs, technical codes, metadata values |

These variables are defined in the combined semantic token block in Section 2.3.

### Google Fonts Loading

Add to **both** `root.html.heex` and `console_root.html.heex`, inside `<head>`, before the stylesheet:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Inter:wght@300;400;500;600;700&display=swap">
```

JetBrains Mono is web-safe enough via the fallback stack; no additional Google Fonts load needed.

### Type Scale

| Usage | Font | Size | Weight | Notes |
|---|---|---|---|---|
| Page title | DM Serif Display | 1.75rem | 400 | letter-spacing: -0.01em |
| Section heading | DM Serif Display | 1.25rem | 400 | |
| Card title | DM Serif Display | 1rem | 400 | |
| Body | Inter | 0.875rem | 400 | line-height: 1.65 |
| UI label | Inter | 0.6875rem | 700 | uppercase, letter-spacing: 0.1em |
| Metadata / secondary | Inter | 0.75rem | 400–500 | `text-neutral` |
| Code / ID | JetBrains Mono | 0.75rem | 400 | |

---

## 5. Animation

Transition tokens (`--sc-transition`, `--sc-transition-slow`) are defined in the combined semantic block in Section 2.3.

All interactive elements use `transition-colors duration-[150ms] ease-in-out` (Tailwind) or the equivalent CSS property. No bounce, no spring. Precise.

---

## 6. Public Interface

### Layout

- Full-page flex column: `navbar → main → footer`
- Max content width: `max-w-5xl mx-auto` for catalog pages

### Header (Navbar)

- Background: `bg-base-200`
- Bottom border: `border-b border-base-300`
- Height: `h-12` (48px)
- Left: logo icon (6px radius square) + "Scientia Cognita" in DM Serif Display 15px
- Right: nav links (Inter 11px semibold, `text-primary`) + avatar (logged in) or login/register buttons (logged out)
- **Avatar (logged in):** 28px circle, `bg-primary text-primary-content`, Inter 700, two initials uppercase. Derived from `@current_scope.user.email` using the algorithm in Section 8 (Avatar). On click: dropdown with Settings / Console / Logout links.
- **Logged out:** `btn btn-ghost btn-sm` (Login) + `btn btn-primary btn-sm` (Register)
- **Theme toggle:** Remains on public side (sun/moon icon, three-state: system/light/dark). Positioned in the navbar right area.

### Footer

```
Scientia Cognita — curated image catalogs
```

- `bg-base-200 border-t border-base-300 text-neutral text-xs text-center p-4`
- No Phoenix framework references anywhere on the site.

### Catalog Grid

- Responsive: `grid-cols-2 sm:grid-cols-3 lg:grid-cols-4`
- Item cards: `bg-base-200 border border-base-300 rounded-box overflow-hidden`
- Hover: `hover:border-primary/40 hover:shadow-sm transition-all duration-[150ms]`
- Error badge: `badge badge-error badge-sm absolute top-2 left-2`

---

## 7. Console Interface

### Theme Forcing

The console uses the `dark` DaisyUI theme permanently. To force this:

- In `console_root.html.heex`, the `<html>` tag gets `data-theme="dark"` as a static attribute.
- The inline theme-detection script (currently in `root.html.heex`) is **not included** in `console_root.html.heex`. The console does not support user theme toggling.
- The `<.theme_toggle />` component is **removed** from `console.html.heex` (both the mobile navbar and the sidebar footer).

```html
<!-- console_root.html.heex -->
<html lang="en" data-theme="dark">
  ...no theme script...
</html>
```

This ensures no flash of wrong theme and no conflict with localStorage.

### Sidebar

- Width: `w-64`
- Background: `bg-base-200`
- Header section: logo icon (6px radius) + "Scientia Cognita" (DM Serif Display 14px, `text-base-content`) + "Console" (Inter 9px uppercase letter-spacing-widest, `text-neutral`)
- Navigation: `menu menu-sm`
  - Active item: `bg-neutral text-primary font-semibold`
  - Hover: `hover:bg-base-300 transition-colors duration-[150ms]`
  - Section labels: Inter 9px uppercase, `text-neutral/60`
- Footer: user initials avatar + email (truncated) + role badge + logout button. No theme toggle.

### Breadcrumb

```
Console › Catalogs › Alpine Flora
```

- Font: Inter 12px, `mb-2`
- Ancestors: `text-primary hover:underline` (clickable links)
- Current page: `text-base-content font-semibold` (not a link)
- Separator: `›` in `text-base-300`
- Placed above the page title on every console page

A reusable `<.breadcrumb>` component is added to `core_components.ex`:

```elixir
attr :items, :list, required: true
# items: [{label: "Console", href: "/console"}, ..., {label: "Alpine Flora"}]
```

### Page Header (Console)

- Title: DM Serif Display 20px, `text-base-content`
- Subtitle (optional): Inter 12px, `text-neutral`
- Actions slot (right-aligned): primary action button + optional secondary ghost buttons
- Placed below breadcrumb, above content

### List Pages (Table Style)

```
[ column headers row ]
[ data row ] [ data row ] [ data row ]
```

- Container: `border border-base-300 rounded-box overflow-hidden`
- Column headers: Inter 10px, uppercase, `tracking-[0.07em]`, `text-neutral/70 font-bold`, `bg-base-200 border-b border-base-300`
- Data rows: `border-b border-base-300 last:border-0`
  - Row height: `h-10` (40px) — single line; `h-14` — two-line (name + metadata)
  - Hover: `hover:bg-base-200/60 transition-colors duration-[150ms]`
  - Name text: Inter 13px `font-medium text-base-content`
  - Metadata (second line, when present): Inter 11px `text-neutral`
  - Action link (rightmost column): `text-primary font-semibold text-xs` with `→` suffix, e.g. `Edit →`

### Edit/Detail Pages

- Layout: single column, `max-w-2xl`
- Section titles: DM Serif Display 16px
- Form field labels: Inter 11px uppercase `font-semibold text-neutral tracking-[0.05em]`
- Action bar: `flex gap-3 pt-4 border-t border-base-300`
  - Save: `btn btn-primary`
  - Cancel: `btn btn-ghost`
  - Delete: `btn btn-error btn-outline` — in a visually separated danger zone at the bottom of the page

### Modals

- DaisyUI `modal modal-box`
- Title: DM Serif Display 18px
- Backdrop: `modal-backdrop`
- Destructive confirm modal: accent/error primary button + ghost cancel button

---

## 8. Component Inventory

### Buttons

| Variant | DaisyUI class | Use |
|---|---|---|
| Primary | `btn btn-primary` | Main actions (Save, Create) |
| Accent | `btn btn-accent` | Highlighted CTAs |
| Outlined | `btn btn-outline btn-primary` | Secondary actions |
| Ghost | `btn btn-ghost` | Tertiary / Cancel |
| Danger | `btn btn-error` | Destructive — always confirm first |
| Danger outline | `btn btn-outline btn-error` | Destructive secondary / "Delete" in danger zone |

All buttons inherit `--radius-field` (4px) from the theme. Font: `font-sans font-semibold`.

### Badges

| Variant | Classes | Use |
|---|---|---|
| Primary | `badge badge-primary badge-sm` | Item counts, tags |
| Success | `badge badge-success badge-sm` | Synced, active |
| Error | `badge badge-error badge-sm` | Failed, error state |
| Warning | `badge badge-warning badge-sm` | Pending, processing |
| Neutral | `badge badge-neutral badge-sm` | Draft, inactive |

### Avatar (Initials)

- Circle: `rounded-full bg-primary text-primary-content font-bold font-sans`
- Sizes: `w-7 h-7 text-xs` (sm), `w-8 h-8 text-sm` (default), `w-10 h-10 text-base` (lg)
- **Initials derivation (single canonical algorithm, used everywhere):**
  1. Take the local part of `user.email` (before `@`)
  2. Split on `.` or `_`
  3. Take the first character of each part, up to two characters, uppercase
  4. If split yields only one part (no `.` or `_`), take the first two characters of that part, uppercase
  - `ivan.kerin@x.com` → `IK`
  - `ivantest@x.com` → `IV`
  - `a.b.c@x.com` → `AB` (only first two segments used)
- The existing console sidebar shows one character (first char of email). Replace with two initials per above logic.
- No image initially; the `<img>` slot is prepared via a `src` attr that can be populated when profile images are added.

### Flash / Toast

- DaisyUI `alert` variants: `alert-info`, `alert-success`, `alert-warning`, `alert-error`
- Positioned: `fixed top-4 right-4 z-50 w-80`
- Auto-dismiss after 5s (existing Phoenix flash behavior unchanged)

### Theme Toggle (Public only)

- Three-state: system / light / dark
- Icon buttons: `btn btn-ghost btn-xs btn-circle`
- Persisted in `localStorage` as `phx:theme`
- **Not present in console** (console is always dark)

---

## 9. Removed: Phoenix Framework References

The following are removed or replaced:

- `home.html.heex` (or equivalent): Replace the default Phoenix welcome page with a Scientia Cognita landing page (catalog listing or a simple branded hero)
- Any `phoenixframework.org` / `github.com/phoenixframework` links in navigation or footer
- Any "Built with Phoenix" or "Peace of mind from prototype to production" text
- Phoenix logo SVGs
- Navigation links to Phoenix docs or Phoenix GitHub in layouts

---

## 10. Files to Create / Modify

| File | Action | Notes |
|---|---|---|
| `assets/css/app.css` | Modify | Replace both DaisyUI theme blocks with new tokens; add `[data-theme=light]`/`[data-theme=dark]` block for semantic aliases + font vars |
| `assets/js/app.js` | Modify | Update topbar color from `#29d` to `#4d86b8` (the hex approximation of `oklch(52% 0.115 218)`, the light-theme primary). The topbar library requires a static hex string; this single value is used for both themes since the topbar only appears during page transitions. |
| `lib/.../components/layouts/root.html.heex` | Modify | Add Google Fonts link; new header (initials avatar, remove Phoenix links); updated footer text |
| `lib/.../components/layouts/console_root.html.heex` | Modify | Add `data-theme="dark"` to `<html>`; add Google Fonts link; remove theme-detection script |
| `lib/.../components/layouts/console.html.heex` | Modify | Remove `<.theme_toggle />`; add breadcrumb slot; consistent sidebar active/hover styles |
| `lib/.../components/core_components.ex` | Modify | Update component classes to match new tokens; add `<.avatar initials={} size={} />` and `<.breadcrumb items={} />` components |
| `lib/.../components/layouts.ex` | Modify | Update `theme_toggle` styling |
| `lib/.../live/page/home.html.heex` (or equivalent) | Modify | Replace Phoenix welcome page with branded content |
| `lib/.../live/console/*.heex` | Modify | Add `<.breadcrumb>` to each console page; consistent table / edit layouts per spec |
| `.gitignore` | Modify | Add `.superpowers/` |

---

## 11. Out of Scope

- Profile image upload (avatar will show initials only; structure prepared for future `<img>` swap)
- Console user theme preference (console is always dark; no toggle)
- Internationalization
- New authentication flows
- New public landing page content beyond removing Phoenix references
