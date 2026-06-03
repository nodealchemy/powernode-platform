# Theme System Reference

> Status: active

> Authoritative reference for theme-aware Tailwind classes used by the React frontend.

## Table of Contents

- [Overview](#overview)
- [Theme Class Mapping](#theme-class-mapping)
- [Component Examples](#component-examples)
- [Automated Fixes](#automated-fixes)
- [Exceptions](#exceptions)

## Overview

All components MUST use theme-aware Tailwind classes (`bg-theme-*`, `text-theme-*`, `border-theme-*`). Hardcoded color classes (e.g. `bg-white`, `text-gray-700`, `bg-red-500`) are forbidden — a pre-commit hook rejects them. The classes resolve via CSS custom properties defined in `frontend/src/index.css`, with light/dark mode toggled by the `dark` class on `<html>`.

> **Theme class allowlist gotcha:** `bg-theme-secondary` / `bg-theme-tertiary` / `bg-theme-*-bg` DO NOT EXIST. Use `bg-theme-surface`, `bg-theme-background-secondary`, or `bg-theme-{success,warning,danger,info}` (no `-bg` suffix). Using non-existent classes silently produces white-on-white rendering.

### Forbidden Patterns

```tsx
// NEVER use hardcoded colors
<div className="bg-white text-black">        // WRONG
<div className="bg-gray-100 border-gray-300"> // WRONG
<div className="bg-red-500 text-red-700">    // WRONG

// EXCEPTION: text-white on colored backgrounds is allowed
<button className="bg-theme-primary text-white">OK</button>  // ALLOWED
```

## Theme Class Mapping

### Background Classes

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `bg-white` | `bg-theme-bg` | Page / app background |
| `bg-gray-50` | `bg-theme-surface` | Card / panel surface |
| `bg-gray-100` | `bg-theme-surface-alt` | Alternate surface |
| `bg-gray-800` | `bg-theme-surface-dark` | Dark surface (e.g., header) |

### Text Classes

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `text-gray-900` | `text-theme-primary` | Primary text |
| `text-gray-700` | `text-theme-secondary` | Secondary text |
| `text-gray-500` | `text-theme-tertiary` | Tertiary / muted text |
| `text-gray-400` | `text-theme-muted` | Placeholder text |

### Border Classes

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `border-gray-200` | `border-theme` | Standard border |
| `border-gray-300` | `border-theme-dark` | Emphasised border |

### Status Colors

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `bg-green-*` | `bg-theme-success` | Success state |
| `bg-red-*` | `bg-theme-error` | Error state |
| `bg-yellow-*` | `bg-theme-warning` | Warning state |
| `bg-blue-*` | `bg-theme-info` | Info state |
| `text-green-*` | `text-theme-success` | Success text |
| `text-red-*` | `text-theme-error` | Error text |
| `text-yellow-*` | `text-theme-warning` | Warning text |
| `text-blue-*` | `text-theme-info` | Info text |

### Interactive Elements

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `bg-blue-600` | `bg-theme-primary` | Primary button |
| `hover:bg-blue-700` | `hover:bg-theme-primary-hover` | Primary hover |
| `bg-gray-200` | `bg-theme-secondary` | Secondary button |
| `hover:bg-gray-300` | `hover:bg-theme-secondary-hover` | Secondary hover |

## Component Examples

### Card

```tsx
<div className="bg-theme-surface border border-theme rounded-lg shadow-sm">
  <h3 className="text-theme-primary font-semibold">Title</h3>
  <p className="text-theme-secondary">Description</p>
</div>
```

### Buttons

```tsx
// Primary
<button className="bg-theme-primary text-white hover:bg-theme-primary-hover">
  Submit
</button>

// Secondary
<button className="bg-theme-secondary text-theme-primary hover:bg-theme-secondary-hover">
  Cancel
</button>

// Danger
<button className="bg-theme-error text-white hover:opacity-90">
  Delete
</button>
```

### Form Input

```tsx
<input
  className="
    bg-theme-bg
    border border-theme
    text-theme-primary
    placeholder:text-theme-muted
    focus:border-theme-primary
    focus:ring-theme-primary
  "
  placeholder="Enter value..."
/>
```

### Status Badge

```tsx
<span className="bg-theme-success/10 text-theme-success px-2 py-1 rounded">Active</span>
<span className="bg-theme-error/10   text-theme-error   px-2 py-1 rounded">Failed</span>
<span className="bg-theme-warning/10 text-theme-warning px-2 py-1 rounded">Pending</span>
```

### Table

```tsx
<table className="w-full">
  <thead className="bg-theme-surface-alt">
    <tr>
      <th className="text-theme-secondary text-left p-3">Name</th>
      <th className="text-theme-secondary text-left p-3">Status</th>
    </tr>
  </thead>
  <tbody>
    <tr className="border-b border-theme hover:bg-theme-surface">
      <td className="text-theme-primary p-3">Item 1</td>
      <td className="text-theme-secondary p-3">Active</td>
    </tr>
  </tbody>
</table>
```

## Automated Fixes

```bash
./scripts/fix-hardcoded-colors.sh
```

## Exceptions

The only allowed hardcoded color is `text-white` on coloured backgrounds:

```tsx
<button className="bg-theme-primary text-white">Submit</button>
<div    className="bg-theme-error   text-white">Error message</div>
<span   className="bg-theme-success text-white">Success</span>
```

### Tailwind Configuration

The project uses **Tailwind CSS 4** with CSS-first configuration.

- Theme classes are defined via CSS custom properties in `frontend/src/index.css`.
- Dark mode uses the `dark` class on the `<html>` element.
- Theme-aware classes (`bg-theme-*`, `text-theme-*`) are custom utilities built on CSS variables.
- Configuration: `frontend/tailwind.config.js`.

---

## Related docs

- [../guides/frontend.md](../guides/frontend.md) — Component patterns, design conventions
- [../guides/accessibility.md](../guides/accessibility.md) — Contrast, focus rings
- Tailwind config: `frontend/tailwind.config.js`

## Materials previously at

- `docs/platform/THEME_SYSTEM_REFERENCE.md`

_Last verified: 2026-06-03_
