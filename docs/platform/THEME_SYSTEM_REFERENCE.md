# Theme System Reference

Unified theme-aware styling documentation for the Powernode platform.

## Core Principle

All components MUST use theme-aware Tailwind classes. NEVER use hardcoded color classes.

## FORBIDDEN Patterns

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
| `bg-white` | `bg-theme-bg` | Page/app background |
| `bg-gray-50` | `bg-theme-surface` | Card/panel surface |
| `bg-gray-100` | `bg-theme-surface-alt` | Alternate surface |
| `bg-gray-800` | `bg-theme-surface-dark` | Dark surface (e.g., header) |

### Text Classes

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `text-gray-900` | `text-theme-primary` | Primary text |
| `text-gray-700` | `text-theme-secondary` | Secondary text |
| `text-gray-500` | `text-theme-tertiary` | Tertiary/muted text |
| `text-gray-400` | `text-theme-muted` | Placeholder text |

### Border Classes

| Hardcoded | Theme Class | Usage |
|-----------|-------------|-------|
| `border-gray-200` | `border-theme` | Standard border |
| `border-gray-300` | `border-theme-dark` | Emphasized border |

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

### Card Component

```tsx
// CORRECT
<div className="bg-theme-surface border border-theme rounded-lg shadow-sm">
  <h3 className="text-theme-primary font-semibold">Title</h3>
  <p className="text-theme-secondary">Description</p>
</div>
```

### Button Component

```tsx
// Primary button
<button className="bg-theme-primary text-white hover:bg-theme-primary-hover">
  Submit
</button>

// Secondary button
<button className="bg-theme-secondary text-theme-primary hover:bg-theme-secondary-hover">
  Cancel
</button>

// Danger button
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
// Success
<span className="bg-theme-success/10 text-theme-success px-2 py-1 rounded">
  Active
</span>

// Error
<span className="bg-theme-error/10 text-theme-error px-2 py-1 rounded">
  Failed
</span>

// Warning
<span className="bg-theme-warning/10 text-theme-warning px-2 py-1 rounded">
  Pending
</span>
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

Run the color fix script to convert hardcoded colors:

```bash
./scripts/fix-hardcoded-colors.sh
```

## Exceptions

The only allowed hardcoded color is `text-white` when used on colored backgrounds:

```tsx
// ALLOWED - text-white on theme colored backgrounds
<button className="bg-theme-primary text-white">Submit</button>
<div className="bg-theme-error text-white">Error message</div>
<span className="bg-theme-success text-white">Success</span>
```

## See Also

- [UI Component Developer Specialist](../frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)
- [React Architect Specialist](../frontend/REACT_ARCHITECT_SPECIALIST.md)
- Tailwind configuration: `frontend/tailwind.config.js`
