# Frontend CLAUDE.md

React TypeScript frontend for Powernode.

## Critical Rules

- `currentUser?.permissions?.includes('name')` - NEVER check roles
- Theme classes only: `bg-theme-*`, `text-theme-*` - no hardcoded colors
- Flat navigation - no submenus
- Actions ALL in PageContainer - none in page content
- Global notifications only - no local success/error
- Imports: `@/shared/`, `@/features/` for cross-feature
- No `console.log` in production, no `any` types

## Context-Aware Documentation

| When working on | Load this documentation |
|-----------------|------------------------|
| `features/ai/*` | [WORKFLOW_FRONTEND_GUIDE.md](../docs/frontend/WORKFLOW_FRONTEND_GUIDE.md) |
| `shared/components/*` | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](../docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) |
| Theme/styling | [THEME_SYSTEM_REFERENCE.md](../docs/platform/THEME_SYSTEM_REFERENCE.md) |
| Permission checks | [PERMISSION_SYSTEM_REFERENCE.md](../docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |
| Forms | [FORM_PATTERNS.md](../docs/frontend/FORM_PATTERNS.md) |
| State management | [STATE_MANAGEMENT_GUIDE.md](../docs/frontend/STATE_MANAGEMENT_GUIDE.md) |
| `features/admin/*` | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](../docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) |

## Key Specialists

- [React Architect](../docs/frontend/REACT_ARCHITECT_SPECIALIST.md)
- [UI Components](../docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)
- [Dashboard](../docs/frontend/DASHBOARD_SPECIALIST.md)
