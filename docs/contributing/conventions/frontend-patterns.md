# Frontend Patterns (React/TypeScript)

Canonical frontend conventions for `frontend/`. Most are mechanically enforced. Deep how-to: [../../guides/frontend.md](../../guides/frontend.md).

| Pattern | Rule | Enforcement |
|---------|------|-------------|
| Colors | Theme classes only: `bg-theme-*`, `text-theme-*` | `hardcoded-color-check.sh` + `pattern-validation.sh` |
| Navigation | Flat structure — no submenus | `pattern-validation.sh` |
| Actions | ALL in PageContainer — none in page content | review |
| State | Global notifications only — no local success/error | review |
| Imports | Path aliases for cross-feature: `@/shared/`, `@/features/` | `convert-relative-imports.sh` |
| Logging | No `console.log` in production — use `import { logger } from '@/shared/utils/logger'` | `console-log-check.sh` + `pattern-validation.sh` |
| Types | No `any` — proper TypeScript types required | `no-any-type-check.sh` + `pattern-validation.sh` |

## Access control (CRITICAL — kept in CLAUDE.md core)

Frontend MUST use **permissions ONLY — NEVER roles** for access control:

```typescript
// ✅ CORRECT
currentUser?.permissions?.includes('users.manage')

// ❌ FORBIDDEN
currentUser?.roles?.includes('admin')
user.role === 'manager'
```

Backend: `current_user.has_permission?('name')` — NEVER `permissions.include?()` (returns objects). Advisory nudge: `permission-not-roles-check.sh`. The principle stays in the core because it is a security boundary; the hook is a backstop, not the source of truth.
