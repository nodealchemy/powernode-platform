# Theme System Reference

> Status: active · Authoritative reference for the theme-aware Tailwind tokens used by the React frontend.

The frontend is **fully themeable**: every color flows through CSS custom properties, so a new
theme is created by editing variable *values* in one file — never component classes. This doc is
the contract that makes that true. Use **only** the tokens listed here; they are the complete set.

- Token utilities + mappings: `frontend/src/assets/styles/tailwind-theme.css` (the `@theme` block)
- Light / dark / contrast values: `frontend/src/assets/styles/themes.css`
- Entry import: `frontend/src/index.css`. Tailwind **v4**, CSS-first (no `tailwind.config.js` colors).
- Dark mode = `dark` class on `<html>`.

## ⚠️ The #1 footgun: text tokens are NOT background tokens

`theme-primary`, `theme-secondary`, `theme-tertiary`, `theme-quaternary` are **TEXT colors**
(`--color-theme-primary` = `--color-text-primary`). In light mode primary text is near-black; in
dark mode it is near-**white**. Tailwind still generates `bg-`/`border-`/`ring-` utilities from
them, so:

```tsx
<div className="bg-theme-primary">…</div>     {/* ❌ paints a TEXT color as a background */}
```

renders a **near-white background in dark mode** — and if its text is also `text-theme-primary`,
you get **white-on-white / invisible** content. This is the single most common theme bug.

| ❌ Never                           | ✅ Use instead                                              | For |
|------------------------------------|------------------------------------------------------------|-----|
| `bg-theme-primary`                 | `bg-theme-interactive-primary` (accent) or `bg-theme-surface` (panel) | button vs card |
| `bg-theme-secondary` / `-tertiary` | `bg-theme-surface-hover` / `bg-theme-surface-secondary`    | subtle fills |
| `border-theme-primary`             | `border-theme` / `border-theme-strong` / `border-theme-focus` | borders |
| `ring-theme-primary`               | `ring-theme-interactive-primary` / `ring-theme-focus`      | focus rings |
| `hover:bg-theme-primary-hover`     | `hover:bg-theme-interactive-primary-hover`                 | this token does **not** exist (inert) |

**Rule of thumb:** `theme-primary/secondary/tertiary/quaternary` → only ever `text-…`. For a
background you want a **surface**, a **background**, an **interactive**, or a **semantic** token.

## Token reference (the complete set)

### Text — use as `text-…` only
| Token | Use |
|-------|-----|
| `text-theme-primary` | Headings, body, primary content |
| `text-theme-secondary` | Secondary content (still WCAG-AA, 4.5:1) |
| `text-theme-tertiary` | Captions/metadata only (3:1 — **not** for body text) |
| `text-theme-quaternary` | Faintest hints |
| `text-theme-on-primary` | Text/icons on an interactive-primary background |
| `text-theme-inverse` | Text on an inverted surface |
| `text-theme-link` / `text-theme-link-hover` | Hyperlinks |

### Surfaces & backgrounds — use as `bg-…`
| Token | Use |
|-------|-----|
| `bg-theme-background` | Page / app shell background |
| `bg-theme-background-secondary` / `-tertiary` | Nested zones, sidebars |
| `bg-theme-background-elevated` / `-muted` | Raised / de-emphasized zones |
| `bg-theme-surface` | Card / panel / table body |
| `bg-theme-surface-hover` | Hover state, subtle header/cell fill |
| `bg-theme-surface-selected` / `-pressed` | Selected / pressed states |
| `bg-theme-surface-secondary` | Alternate/striped surface |
| `bg-theme-surface-disabled` | Disabled control surface |

### Interactive (brand accent) — use as `bg-…` with `text-theme-on-primary`
| Token | Use |
|-------|-----|
| `bg-theme-interactive-primary` (+ `-hover` / `-active` / `-disabled`) | Primary buttons, toggles, selected chips, accent fills |
| `bg-theme-interactive-secondary` (+ `-hover` / `-active` / `-disabled`) | Secondary buttons |

### Semantic status — the `fg`/`bg`/`border` triad
For `success`, `warning`, `error`, `danger`, `info`:
| Slot | Token | Use |
|------|-------|-----|
| Foreground | `text-theme-success-fg` | Status text / icon (saturated, readable) |
| Background | `bg-theme-success-bg` | Status pill / banner fill (tint) |
| Border | `border-theme-success-border` | Status outline |

```tsx
<span className="bg-theme-success-bg text-theme-success-fg border border-theme-success-border px-2 py-0.5 rounded">Active</span>
```
> The bare `text-theme-success` (no `-fg`) resolves to the same value as `-fg`, but prefer the
> explicit `-fg`/`-bg`/`-border` triad — it documents intent and is what the lint guard expects.

### Borders — use as `border-…`
`border-theme` (standard) · `border-theme-light` · `border-theme-strong` · `border-theme-focus`
· `border-theme-{success,warning,error,danger,info}`.

### Focus rings
`ring-theme-focus` · `ring-theme-interactive-primary`. **Never** `ring-theme-primary`.

## Component examples (all tokens real)

```tsx
// Card / panel
<div className="bg-theme-surface border border-theme rounded-lg shadow-sm">
  <h3 className="text-theme-primary font-semibold">Title</h3>
  <p className="text-theme-secondary">Description</p>
</div>

// Primary button
<button className="bg-theme-interactive-primary text-theme-on-primary hover:bg-theme-interactive-primary-hover rounded px-3 py-2">
  Submit
</button>

// Secondary button
<button className="bg-theme-interactive-secondary text-theme-primary hover:bg-theme-interactive-secondary-hover rounded px-3 py-2">
  Cancel
</button>

// Table
<table className="min-w-full divide-y divide-theme">
  <thead className="bg-theme-surface-hover">
    <tr><th className="text-theme-secondary text-left p-3">Name</th></tr>
  </thead>
  <tbody className="bg-theme-surface divide-y divide-theme">
    <tr className="hover:bg-theme-surface-hover">
      <td className="text-theme-primary p-3">Item</td>
    </tr>
  </tbody>
</table>
```

> The standard `<Button>` / `<Badge>` UI components already encode these tokens — prefer them
> over hand-rolled buttons/badges.

## Theming: how to add or change a theme (minimal work)

Three layers, each referencing the one below:

```
component className  →  @theme token            →  semantic var           →  base scale
bg-theme-surface        --color-theme-surface       --color-surface           --color-neutral-50
text-theme-primary      --color-theme-primary       --color-text-primary      --color-neutral-900
```

- **To re-theme:** edit only the **semantic var** values in `themes.css` (the `:root` / light
  block ~line 284, the dark block ~line 359, plus `prefers-contrast` / `forced-colors`). Components
  and `@theme` tokens never change. This is the entire surface area of a theme.
- **To add a brand color:** add a base scale + point the semantic vars at it.
- **Never** hardcode hex or Tailwind palette colors (`bg-white`, `text-gray-700`, `bg-red-500`) in
  components — the `hardcoded-color-check.sh` hook rejects them. Only exception: `text-white` on a
  guaranteed-dark colored background.

## Enforcement

- **Edit-time hook:** `.claude/hooks/theme-token-check.sh` flags text-token-as-background/border/ring
  (`bg-/border-/ring-theme-{primary,secondary,tertiary,quaternary}`) and the inert
  `*-theme-primary-hover` token.
- **Adherence scan:** `scripts/pattern-validation.sh` → "Forbidden text-token-as-background".
- **Hardcoded colors:** `.claude/hooks/hardcoded-color-check.sh` + `./scripts/fix-hardcoded-colors.sh`.

## Related docs
- [../guides/frontend.md](../guides/frontend.md) — component patterns
- [../guides/accessibility.md](../guides/accessibility.md) — contrast, focus rings

_Last rewritten 2026-06-28 against the live `@theme` inventory (corrected phantom tokens + the
`bg-theme-primary` button footgun that this doc previously taught)._
