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

## Extension state (Redux)

Extensions compose into the platform through `featureRegistry` — routes, nav
items, settings tabs, channels, component slots. **State is the same shape of
seam**, via `injectReducer` from `@/shared/services`.

An extension that defines a Redux slice must register its reducer, or the slice
exists nowhere and every selector reading it gets `undefined`. That is not
hypothetical: an extension shipped a complete slice mounted in no store, and it
went unnoticed only because nothing rendered the components that would have
thrown on first render.

```typescript
// extension register() — beside the featureRegistry calls
import { injectReducer } from '@/shared/services';
import billingReducer from '@myext/shared/slices/billingSlice';

export function register(): void {
  injectReducer('billing', billingReducer);
  featureRegistry.registerRoutes('myext', [ /* ... */ ]);
}
```

Type it from the **extension** side — core must never name an extension, so it
exposes an empty, augmentable `ExtensionState` that declaration merging fills:

```typescript
// beside the slice
declare module '@/shared/services' {
  interface ExtensionState {
    billing: BillingState;
  }
}
```

Three properties worth understanding rather than working around:

- **Ordering is already safe.** `register()` runs synchronously at module load
  (`extensionLoader`'s eager glob), and runtime extensions are awaited in
  `index.tsx` — both before the first render. A reducer injected from
  `register()` is present before anything selects it.
- **`RootState` applies `Partial<>` to extension state, deliberately.** Slices
  genuinely do not exist until `register()` runs, and a runtime extension that
  exceeds the boot timeout registers *after* the first render. So read with
  `?.` and a fallback. Asserting the slice is present would type-check and then
  throw — the exact failure this seam replaced.
- **`injectReducer` is idempotent.** Re-registering a key is a no-op, so HMR and
  a double-invoked `register()` cannot reset live slice state.

Do NOT create a second store inside an extension. Two stores means two sources
of truth, and breaks devtools and cross-cutting selectors.

Covered by `frontend/src/shared/services/injectReducer.test.ts`.
