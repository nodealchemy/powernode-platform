# Extension DB & Registry Contributions

How an extension adds schema, data, and governance **without core depending on it**. The rule is
inverted-dependency: **core defines generic seams; each extension registers into them at boot**. Core
never names an extension. Enforced by the blocking `core-purity-check.sh` (forbidden names derived
dynamically from `extensions/private/*`) + the `schema.rb` leak guard. Companion:
[migrations-and-seeds.md](migrations-and-seeds.md).

## The seam pattern (why this exists)

Before: core was littered with `defined?(SomeExtension::X)` guards and hardcoded extension lists. After:
core exposes a registry; the extension's `Engine` calls a `register_*` method during initialization. When
the extension is absent (core mode), the registry is simply empty and every accessor degrades safely. To
add an extension you should need **zero edits to core**.

| Contribution | Core seam | Extension registers |
|---|---|---|
| **Tables** | `ExtensionRegistry.owned_prefixes` / `table_private?` drive the dumper exclusion + leak guard | Own a `<ext>_` table prefix; ship a baseline in `extensions/<name>/server/db/migrate/` (banded — see migrations doc). Private prefixes are excluded from the public `schema.rb`. |
| **Permissions** | `Permissions.register_catalog(namespace:)` + dynamic `all_permissions` | Declare extension-prefixed permissions (`<ext>.<resource>.<action>`) in the engine catalog. The enforced⊆defined guardrail covers them. |
| **Roles** | `Permissions.register_roles(namespace:)` + dynamic `all_roles` | Register GLOBAL roles (`role_type: "user"` = account-assignable) granting extension permissions by name. |
| **Audit actions/sources** | `AuditActions.register_actions(namespace, actions)` / `register_sources` + dynamic `all_actions`/`all_sources` (validated by proc, re-evaluated per write) | Register the action + source tokens it logs. `AuditLog` lives in core; extensions log through it. Do **not** widen core's fixed token lists. |
| **Seeds** | The core seed orchestrator loads each extension's `seed_orchestrator` contract | Seed extension-owned content (KB articles, roles, demo data) from the extension, never from core seeds. Must be idempotent. |
| **Frontend components** | `featureRegistry.registerComponentSlots` (+ build-time `__EXTENSIONS__.includes(...)` gate, lazy `@ext/<name>/...` imports) | Mount pages/nav/slots into core mount points; gate routes on the extension being present. |
| **Optional capabilities** | A core `*Bridge` (e.g. a billing bridge): core calls null-safe accessors; absent extension = safe default | Register model classes / handlers into the bridge at boot. |

## Rules

| Rule | Detail |
|---|---|
| Core never depends on an extension | No `<Namespace>::`, `extensions/private/<name>` path, or `@ext/<name>` alias in core source. Route through a generic seam. |
| Cross-namespace calls go through interfaces | Never reach into another namespace's models directly — use a service/registry boundary. |
| Dynamic union, disabled-excluded | Every `all_*` accessor is `core ∪ registered-extensions`, and a disabled extension contributes nothing. Adding/removing an extension changes the set with no core edit. |
| Commit discipline | Extension code commits **inside** its own submodule first; the parent then bumps the pointer. Never commit extension files from the parent. |
| Validate both modes | After any seam change, verify **core mode** (extension disabled) and **full mode** (enabled): `zeitwerk:check`, `permissions:check`, `db:seed`, and the leak guard must pass in both. |

## Adding an extension that touches the DB — checklist

1. Pick a unique `<ext>_` table prefix; declare `owned_prefixes` in the engine.
2. Generate a baseline migration in the extension (correct timestamp band; UUIDv7 PKs).
3. Register permissions / roles / audit tokens via the seams above (extension-prefixed names).
4. Provide a `seed_orchestrator`; seed only extension-owned, idempotent content.
5. Mount frontend via `registerComponentSlots`; gate on `__EXTENSIONS__`.
6. Run the both-modes validation set. Confirm `schema.rb` (regenerated core-mode) shows **0** of your
   private tables if the extension is private.
