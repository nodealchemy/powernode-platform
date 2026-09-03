# Migrations & Seeds (Rails API)

Canonical conventions for the **0.4.0 baseline schema** in `server/` and `extensions/*/server/`.
The 616 historical migrations were squashed into **7 baselines** (one bootstrap + one per owner); new
schema changes are incremental migrations on top. Deep how-to: [../../guides/backend.md](../../guides/backend.md).
Backstopped by `scripts/pattern-validation.sh` (leak guard + UUID-PK convention).

## Baseline architecture (post-squash)

| Concern | Rule |
|---|---|
| Bootstrap | `setup_uuidv7` runs first — defines the portable `uuidv7()` SQL function (see below) before any `create_table` uses it as a default. |
| Per-owner baselines | One baseline per owner: core + each public extension are **banded `≤ S`** (S = the max public timestamp); each **private** extension is banded **`> S`** so `schema:load` (core) then `migrate` (private) replays cleanly. |
| Where baselines live | Core/public baselines in `server/db/migrate/`; an extension's baseline in `extensions/<name>/server/db/migrate/`. An extension owns its own schema. |
| Cross-owner FKs | A foreign key whose endpoints span owners is emitted in the **later-band** owner's baseline (e.g. an extension→core FK lives in the extension baseline), so core builds standalone. |

## Adding a migration

| Situation | Do |
|---|---|
| New core table/column | Add a normal migration in `server/db/migrate/`. Regenerate `schema.rb` in **core mode only** (see split rule). |
| New extension table | Add the migration in `extensions/<name>/server/db/migrate/` with a timestamp in that extension's band. Prefix the table with the extension's `<ext>_` prefix. |
| Reference columns | `t.references` **already creates an index** — never add a separate `add_index` for it. Customize inline: `t.references :account, index: { unique: true }`. |
| PK type | Every table is `id: :uuid, default: -> { "uuidv7()" }`. Never `string :id` (the old string-PK form was eliminated). |

## UUIDv7 primary keys

| Rule | Detail |
|---|---|
| Default | All PKs are native `id: :uuid` with DB default `uuidv7()` (time-ordered v7 — index-friendly, unlike random v4). |
| The shim | `uuidv7()` is a portable PG16 SQL function (no extension). It is **named to match the PG18 native function**, and is self-skipping when a native `uuidv7()` exists — on a future PG18 upgrade, drop the shim with zero schema change. |
| Self-bootstrapping dump | `schema.rb` emits a guarded `CREATE FUNCTION uuidv7() … unless it exists` before the tables (via `config/initializers/uuidv7_schema_dump.rb`), so a fresh `schema:load` works without the migration. |
| Ruby-side IDs | Generate IDs in app code with `UUID7.generate` (the `UuidGenerator` concern), **never** `SecureRandom.uuid` (v4). |

## Public / private schema split (CRITICAL)

| Rule | Detail |
|---|---|
| `schema.rb` is **core-mode-only** | It must contain **only** core + public-extension tables. Regenerate it via a **core-mode** `db:schema:dump` (private extensions disabled). A full-mode dump re-emits private tables + cross-owner FKs and **leaks**. |
| Auto-dump disabled | `ActiveRecord.dump_schema_after_migration = false` (`config/initializers/schema_dump_isolation.rb`) so a full-mode `migrate` never silently re-leaks. Rebuild `schema.rb` deliberately: move it aside → core-mode `migrate` → core-mode `schema:dump`. |
| Leak guard | `pattern-validation.sh` greps the committed `schema.rb` for any private-prefix table ref (prefixes derived dynamically from `extensions/private/*`). Must be 0. The enforcement is the `SchemaDumper` prepend; the scan is the backstop. |

## Table-prefix isolation

Each extension owns a `<ext>_` table prefix (e.g. public `system_`, `system_sdwan_`, `marketing_`,
`supply_chain_`; private extensions own their own prefixes). Core tables carry **no** extension prefix.
`ExtensionRegistry.owned_prefixes` / `table_private?` drive the dumper exclusion and the leak guard — both
generic, so adding an extension needs no edit to either. A model maps to its prefixed table with an
explicit `self.table_name` (do not rely on a base-class prefix — it would drop sub-domain prefixes).

## Index naming

Baselines emit **Rails-generated** index names (`index_<table>_on_<cols>`, auto-truncated past 63 chars).
Keep an explicit `name:` **only** when the line carries `using:` (gin) or `where:` (partial) — those can
collide with the generated btree name on the same column. Drop true duplicate indexes; keep
unique/partial/GIN variants on the same column.

## Seeds

| Rule | Detail |
|---|---|
| Tiers | `db/seeds.rb` is a thin orchestrator. **core** (always) seeds the minimum a self-hosted install needs; **baseline** (global foundational content, nullable `account_id`) is gated; **demo** is gated by `POWERNODE_SEED_DEMO`. |
| Idempotency (MANDATORY) | `db:seed` must produce the complete set on the **first** run and be a **no-op** on re-run. Validate only from a `truncate_all` clean baseline — a dirty DB gives false greens. Make version/counter columns create-only; upsert on a stable natural key (`source_key`/`name`), not slug. |
| One writer | **Never** run two `db:seed` (or seed + a migration) against the same DB concurrently — they collide. One DB writer at a time. |
| Extension seeds | Each extension contributes via its `seed_orchestrator` contract (loaded by the core orchestrator); extension-specific content (KB articles, roles, permissions, audit actions) is registered through the extension's engine, never core seeds. |
| Page/data extraction | Large inline seed blocks (pages, demo content) live in `db/seeds/*.rb` data files, not inline in the orchestrator. |
| Declared policy rows have ONE writer | An agent seed writes **identity, prompt, approval chain, trust, tool_access and skills only**. Declared intervention-policy rows (an agent's action-category set) are written by the governance **reconciler** on every boot from the declarations it consumes — never upserted by the agent seed, which runs once at first boot and then never again, so a policy added to a seed after first boot would never reach an established install. The system extension's `System::Governance::PolicyReconciler` (over `PolicyDeclarations::POLICY_SETS`) is the reference implementation and its Supply Chain Manager seed the reference shape; the older system-extension seeds that still upsert their own rows are grandfathered pending a filed rewrite — do not copy that shape into a new seed. |

## Gotchas (do not relearn the hard way)

- **Renames break cutover.** The 0.4.0 table renames make the new schema incompatible with an old live
  DB's table names — a deployment cannot cut over until a data-migration ETL maps old→new. Keep live on
  its current schema until then.
- **Private extensions may be files-only on a rig** (no `.git`). Commit their changes **inside** the real
  submodule, then bump the pointer in the parent — never commit extension files from the parent.
- **Fresh build needs PG extensions first**: `ltree`, `pg_trgm`, `pgcrypto`, `vector` (created by a
  superuser; the app role may lack `CREATE EXTENSION`), then `db:schema:load` (+ `migrate` for private).
