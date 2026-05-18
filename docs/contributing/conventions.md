# Conventions

> Human-applicable patterns and rules for contributing code to Powernode.

> Status: active

This is the human contributor's distillation of the conventions documented in the root CLAUDE.md. It excludes the AI-only instructions and focuses on what you need when writing code, reviewing PRs, or interpreting an existing pattern.

## Table of Contents

- [Permission-based access control](#permission-based-access-control)
- [Frontend patterns](#frontend-patterns)
- [Backend patterns](#backend-patterns)
- [Cryptographic material safety](#cryptographic-material-safety)
- [Bulk operation safety](#bulk-operation-safety)
- [Design principles](#design-principles)
- [Architecture principles](#architecture-principles)
- [Frontend linting](#frontend-linting)
- [Terminology](#terminology)

## Permission-based access control

**Frontend must use permissions only — never roles for access control.**

```typescript
// CORRECT
currentUser?.permissions?.includes('users.manage')

// FORBIDDEN
currentUser?.roles?.includes('admin')
user.role === 'manager'
```

**Backend:** use `current_user.has_permission?('name')`. Never `current_user.permissions.include?(...)` — that compares against `Permission` objects, not strings, and will silently return `false`.

The canonical permissions registry is seeded by `server/app/services/permission_seeder.rb` together with the topic-scoped seed files (e.g., `server/db/seeds/ai_autonomy_permissions.rb`). The reference page is [reference/permissions.md](../reference/permissions.md).

## Frontend patterns

| Pattern | Rule |
|---------|------|
| Colors | Theme classes only: `bg-theme-*`, `text-theme-*` |
| Navigation | Flat structure — no nested submenus |
| Actions | All page actions in `PageContainer` — none inline in page content |
| State | Global notifications only — no local success/error toasts |
| Imports | Path aliases for cross-feature: `@/shared/`, `@/features/` |
| Logging | No `console.log` in production. Use `import { logger } from '@/shared/utils/logger'` |
| Types | No `any`. Proper TypeScript types required |

The full theme class catalog (and the four `bg-theme-*-bg` names that **do not exist**) is in [getting-started/04-troubleshooting.md](../getting-started/04-troubleshooting.md#theme-classes-that-do-not-exist) and the [reference theme system page](../reference/theme-system.md).

## Backend patterns

| Pattern | Rule |
|---------|------|
| Controllers | Under `Api::V1` namespace; inherit `ApplicationController` |
| Responses | Mandatory: `render_success(data: ...)`, `render_error(message: ..., status: ...)` |
| Worker jobs | Inherit `BaseJob`; use `execute()` method; HTTP-only to the server |
| Ruby files | `# frozen_string_literal: true` pragma required |
| Logging | `Rails.logger.<level>` — never `puts` or `print` |
| Migrations | `t.references` auto-creates an index. Never `add_index` for reference columns. Use `t.references :account, index: { unique: true }` instead |
| Namespaces | Use `::` separator in `class_name:` — e.g. `Ai::AgentTeam`, not `AiAgentTeam` |
| Foreign keys | Namespaced FK prefixes: `Ai::` → `ai_`, `Devops::` → `devops_`, `BaaS::` → `baas_` |
| JSON columns | Lambda defaults: `attribute :config, :json, default: -> { {} }` — never `default: {}` |
| Controller size | Stay under 300 lines. Extract query logic to services, serialization to concerns |
| Eager loading | Always `.includes()` when iterating associations |
| Webhook receivers | Return 200/202 on processing errors — never 500 (causes provider retry storms) |

## Cryptographic material safety

These rules are absolute. They apply equally to humans and AI agents.

| Rule | Details |
|------|---------|
| No key output | Never output, log, display, echo, or transmit private keys, API secrets, seed phrases, mnemonics, or signing material |
| No keys in code | Never store keys, secrets, or credentials in source files, scripts, configs, env files, or docs |
| No CLI key generation | Never generate private keys via `rails runner`, `rake`, or `irb` where they could appear in shell history |
| Vault-only storage | All key generation happens inside Vault or the `WalletKeyService` (which stores directly to Vault) |
| Audit all key operations | Log every generate/import/revoke/sign to `Trading::AuditLog` |
| No keys as arguments in logs | Never pass private keys as function arguments that could surface in stack traces |
| Guide, don't handle | When helping a user set up a wallet, walk them through the UI/API — never handle the key material directly |

## Bulk operation safety

| Rule | Details |
|------|---------|
| State the count | Before any bulk operation (approve, reject, delete, update), say "this will affect N items" |
| Confirmation threshold | Operations affecting more than 5 items require explicit confirmation |
| Show samples | For bulk operations, show the first 3 and last 1 items |
| Never batch-approve | Training decisions, permission grants, and financial operations are reviewed individually |

## Design principles

| Principle | Rule |
|-----------|------|
| Reuse first | Search the platform for existing infrastructure (skills, services, components) before proposing a new one |
| Quality gates | Run `npx tsc --noEmit` after TS changes; verify Ruby syntax + relevant spec after `.rb` changes |
| Verify seeds | After seed changes, run `rails db:seed` and watch for association/validation errors |
| Stop and ask | After 3 failed attempts at the same fix, stop and ask the user. Do not try a 4th approach |
| Audit sessions | When asked to audit, save findings — do not implement changes unless explicitly told to |
| Verify changes | Ruby: syntax check + spec. TypeScript: `tsc --noEmit`. Migrations: `rails db:migrate:status`. Seeds: `rails db:seed` |
| Dead reference cleanup | After deleting a file, `grep -r` for all import/require references and remove them in the same PR |

## Architecture principles

| Principle | Rule |
|-----------|------|
| Pull, never push | Downstream managers pull from upstream sources. Upstream services never push to downstream |
| Extension isolation | Each `extensions/*` is self-contained. Extensions depend on core; core never depends on extensions |
| Service boundaries | Cross-namespace communication goes through service interfaces, never direct model access across namespaces |

## Frontend linting

The frontend uses a multi-tier ESLint configuration to balance security, code quality, and developer experience.

### Configuration files

| File | Purpose | Usage |
|------|---------|-------|
| `.eslintrc.js` | Daily development; balanced security with smart overrides | `npm run lint` |
| `.eslintrc.production.js` | Strict production-readiness checks | `npm run lint:production` |
| `.eslintrc.security.js` | Security-focused audit | `npm run lint:security` |

### npm scripts

```bash
npm run lint            # daily linting
npm run lint:fix        # auto-fix
npm run lint:security   # CI security audit
npm run lint:production # production readiness
npm run lint:check      # check ESLint config itself
```

### Object injection rule strategy

ESLint's `security/detect-object-injection` flags dynamic object property access. The plugin generates many false positives in our admin context. Our approach:

- **Development:** disabled globally (too many false positives).
- **Admin components:** disabled — authenticated and permission-controlled.
- **UI design system components:** disabled — props are controlled.
- **Public components:** enabled with explicit overrides.
- **Production:** warn level with required `eslint-disable` comments.

Safe patterns (authenticated context):

```typescript
const service = healthStatus.services[serviceName];
const classes = themeClasses[variant];
const value = formData[fieldName];
```

Dangerous patterns (always avoided):

```typescript
const value = obj[userInput];   // never accept user input as a key
eval(userCode);                 // banned
obj.__proto__ = malicious;      // prevented
```

### Rule overrides by context

| Path | Rule overrides |
|------|----------------|
| `**/admin/**/*.tsx` | `security/detect-object-injection: 'off'`, `security/detect-possible-timing-attacks: 'off'` |
| `**/shared/components/ui/**/*.tsx` | `security/detect-object-injection: 'off'` |
| `**/public/**/*.tsx` | `security/detect-object-injection: 'error'`, `security/detect-possible-timing-attacks: 'error'` |
| `**/*.test.tsx` | `no-console: 'off'`, `security/detect-object-injection: 'off'` |

### Build interaction

If the production lint config breaks your build, run with the dev config:

```bash
ESLINT_NO_DEV_ERRORS=true npm run build
```

### CI integration

The validation workflow runs `npm run lint` on every PR. The stricter `lint:security` and `lint:production` runs are reserved for release branches.

## Terminology

| Term | Meaning | Don't confuse with |
|------|---------|--------------------|
| `server/` | Rails app directory on disk | "Backend directory" |
| `powernode-backend` | Systemd service name (`powernode-backend@default`) | "Server service", "Rails service" |
| `worker/` | Standalone Sidekiq app directory | "Job runner" |
| `powernode-worker` | Systemd service name (`powernode-worker@default`) | "Sidekiq service" |

---

## Materials previously at

- Sections of the root CLAUDE.md (Permission-Based Access Control, Frontend Patterns, Backend Patterns, Cryptographic Material Safety, Bulk Operation Safety, Design Principles, Architecture Principles, Terminology)
- `docs/frontend/ESLINT_GUIDE.md`

_Last verified: 2026-05-17_
