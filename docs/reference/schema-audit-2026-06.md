# Schema Audit — 2026-06 (pre-0.4.0 DB refactor)

**Status:** report-only (per CLAUDE.md "Audit = report only"). Drives Phase 4 (squash+rename+cleanup),
Phase 6 (billing consolidation), Phase 9 (curated data migration). Removal/consolidation actions are
applied on the clean rig, never on the live `powernode_development` DB.

## Methodology & data sources
- **Reflection** (clean rig `powernode_clean_development`, full + core mode): `scripts/audit/table_model_map.rb`
  → table→model→owner map (`tmp/audit/table_model_{full,core}.tsv`). Owner derived from model source path.
- **Live catalog stats** (live `powernode_development`, read-only, instant — `pg_stat_*`/`pg_class`):
  row estimates (`n_live_tup`), index scans, duplicate-index groups, index definitions
  (`tmp/audit/live_*.tsv`, `combined_tables.tsv`).
- **Caveat:** `n_live_tup` is a planner estimate (last ANALYZE), not exact; treat small counts as
  approximate. Exact `COUNT(*)` is run at migration time, not here (avoided to keep zero load on live).

## Executive summary
- **515 app tables** (+ `schema_migrations`, `ar_internal_metadata`). Ownership: **core 270, system 107
  (`system_*`+`sdwan_*`), business 58 (private), trading 36 (private, DISABLED), supply-chain 28,
  marketing 9, gem 2 (flipper), 2 true orphans, oauth gem tables.**
- **The cleanup win is in INDEXES + RENAMES, not table drops.** Only **2 true orphans** to drop.
- **42 duplicate-index groups** → ~36 true redundant pairs to drop, 6 semantically-distinct to KEEP.
- **All 511 PKs are UUID v4** (`gen_random_uuid()`) despite the `uuid7` gem + "UUIDv7" claims → switch
  to **UUIDv7** via a PG16 `uuidv7()` SQL function (Decision 8).
- **Index naming** is split `idx_*` (manual) vs `index_*` (Rails) → standardize (Decision 9); this is
  the *same* fix as the duplicate-index cleanup.
- Locked decisions: (1) uniform `<ext>_` prefixes; (2) public+private schema split; (3) aggressive
  cleanup; (4) broad hardening; (5) autonomy; (6) live untouched; (7) curated data migration;
  (8) UUIDv7; (9) standardized index naming.

## 1. Ownership map (authoritative, from reflection)
| Owner | Tables | Prefix status | Schema visibility |
|---|---|---|---|
| core | 270 | (no prefix) | public `schema.rb` |
| system | 107 | `system_*` (80) + `sdwan_*` (27) → fold to `system_sdwan_*` | public `schema.rb` |
| supply-chain | 28 | `supply_chain_*` ✓ | public `schema.rb` |
| marketing | 9 | `marketing_*` ✓ | public `schema.rb` |
| business | 58 | mixed (rename → `business_*`) | **private** (excluded from public `schema.rb`) |
| trading | 36 | `trading_*` ✓ (DISABLED) | **private** (not created in clean install) |
| gem (flipper) | 2 | `flipper_*` | public `schema.rb` (keep) |
| orphan | 2 | — | DROP |

Full per-table data: `tmp/audit/combined_tables.tsv` (owner, table, has_model, n_live_tup, idx_scan).

## 2. Orphan / no-model tables → verdicts
| Table | Owner | rows (est) | Verdict | Evidence |
|---|---|---|---|---|
| `cookie_consents` | core | 0 | **DROP** | no model anywhere, 0 rows, 0 scans |
| `ai_publisher_earnings_snapshots` | business | 0 | **DROP** | no model (grep empty), 0 rows; legacy AI-publisher artifact |
| `oauth_access_grants` | Doorkeeper gem | 16 | **KEEP** | OAuth gem-managed, real data |
| `oauth_access_tokens` | Doorkeeper gem | 5 | **KEEP** | OAuth gem-managed, real data |
| `oauth_applications` | Doorkeeper gem | 16 | **KEEP** (foundational) | OAuth apps — migrate |
| `flipper_features`/`flipper_gates` | flipper gem | 12/12 | **KEEP** (foundational) | feature-flag state |
| `ai_skills_mcp_servers` | core | 0 | **KEEP** | HABTM join (ai_skills × mcp_servers) |

Removal discipline: only the 2 zero-row, model-less, scan-less tables are dropped. Everything
uncertain is kept + flagged. No table dropped without appearing on this list.

## 3. Index analysis (Decisions 3 + 9)
**42 duplicate-index groups** (same table+columns). Most are `idx_<t>_on_<col>` (manual short) AND
`index_<t>_on_<col>` (Rails default) on the SAME FK column → **redundant, drop one** (keep the
Rails-conventional name; the squashed baselines emit only Rails-generated names, eliminating these by
construction). **KEEP-both (semantically distinct, NOT redundant):**
| Table | Index | Why keep |
|---|---|---|
| `system_packages` | `idx_packages_name_trgm` | GIN trigram (vs btree `index_*_on_name`) — fuzzy search |
| `sdwan_peer_keys` | `idx_sdwan_peer_keys_one_active_per_peer` | partial-UNIQUE constraint |
| `trading_portfolios` | `idx_trading_portfolios_unique_session` | partial-UNIQUE |
| `trading_portfolios` | `index_trading_portfolios_unique_proving_ground` | partial-UNIQUE |
| `supply_chain_attributions` | `idx_attributions_component` | UNIQUE (drop the non-unique twin) |
| `supply_chain_build_provenances` | `idx_build_provenance_attestation` | UNIQUE (drop non-unique twin) |

Standardization rule (Decision 9): baselines use `t.references`/`add_index` with NO manual `name:`
→ canonical `index_<table>_on_<cols>` (Rails auto-truncates >63 chars). Manual names only for the
KEEP-both distinct indexes above + documented >63-char exceptions. Full list: `tmp/audit/live_dup_index_defs.tsv`.

## 4. UUIDv7 (Decision 8)
All 511 PK tables default `id: :uuid, default: gen_random_uuid()` (**v4**). The 4 `id:false` HABTM
join tables have no PK (correct). Plan: add a PG16-compatible `uuidv7()` SQL function (first core
baseline, after `pgcrypto`); every PK defaults `uuidv7()`. Fix `config/initializers/uuid_primary_keys.rb`
(`primary_key_type: :string` → `:uuid`). New rows v7; migrated rows keep existing UUIDs (FK integrity).
Evaluate the `uuid7` gem (keep only if used for app-layer non-PK id generation; the DB default is the
guarantee).

## 5. Table prefix rename map (Decision 1)
Targets: **business (58 tables → `business_*`)** + **system `sdwan_*` (27 → `system_sdwan_*`)**.
trading/marketing/supply_chain already compliant.
### §5a — Rename map (84 tables, NO collisions; artifact `tmp/audit/rename_map.tsv`)
Rule: `new = "business_" + (old − leading "ai_")` for business (strip the misleading core-`ai_`);
`sdwan_*` → `system_sdwan_*`. Already-compliant: `trading_`/`marketing_`/`supply_chain_`.
- **business: 58** → `business_*`: `ai_credit_*`→`business_credit_*`, `ai_marketplace_*`→
  `business_marketplace_*`, `ai_sla_*`/`ai_outcome_*`/`ai_publisher_*`/`ai_account_credits`→`business_*`;
  `baas_*`→`business_baas_*` (sub-domain kept — avoids `baas_subscriptions`↔`subscriptions` clash),
  `mcp_*`→`business_mcp_*`; `marketplace_{listings,reviews,subscriptions}`→`business_marketplace_*`;
  `subscriptions`/`plans`/`payments`/`invoices`/`reseller_*`/`revenue_*`/`reconciliation_*`/etc.→`business_*`.
- **sdwan: 26** → `system_sdwan_*`.
- **Collision check: NONE** — `marketplace_categories` is NOT a current table (dropped in the
  marketplace refactor), so `ai_marketplace_categories`→`business_marketplace_categories` is unique.
- **table_name MECHANISM: explicit `self.table_name = "business_…"` per model** (58; 43 already
  explicit → change value, ~15 add). A base-class `table_name_prefix` is REJECTED — Rails convention
  drops sub-domains (`BaaS::Customer`→`business_customers`, losing `business_baas_customers`). Spec
  asserts every business model's table starts `business_`.
- `ai_publisher_earnings_snapshots` (model-less) → PRESERVE + rename `business_publisher_earnings_snapshots`
  (it's a payment feature; see §5b — do not drop without the user's call).

### §5b — Deep-verification corrections (rename-map subagent, all VERIFIED)
1. **4 tables are CORE, not business — exclude from `business_` rename:** `ai_agent_templates`,
   `ai_agent_installations`, `ai_agent_reviews`, `ai_template_usage_metrics` have CORE models
   (`server/app/models/ai/*`). Yet business's `create_agent_marketplace_tables.rb` *also* creates
   `ai_agent_templates` (isolation smell). **Squash fix:** core baseline owns these; remove their
   creation from the business baseline. They stay `ai_agent_*` (core).
2. **`table_name` mechanism — explicit is MANDATORY (sharper reason):** `Ai::` and `Marketplace::`
   are namespaces **shared with core**, and core sets their module `table_name_prefix` (`ai_` in
   `server/app/models/ai.rb`; `app_` in core `marketplace.rb`). Rails resolves module-nesting prefix
   BEFORE any base-class prefix, so a business `Ai::CreditPack` would resolve to `ai_…` regardless of
   a base class — business cannot override it. ⟹ explicit `self.table_name` on all 59. **Also delete
   the vestigial `app_` `table_name_prefix` in business `marketplace.rb:9`** (the `apps`/`app_*` family
   is already dropped).
3. **`ai_marketplace_*` is LIVE, not legacy** — used by `Ai::MarketplaceService`/
   `MarketplacePaymentService` + `agent_marketplace_controller` + `publisher_controller` + spec.
   Both it and `marketplace_*` (Marketplace::Listing) are distinct live subsystems → both rename to
   `business_*` (collision-free, different suffixes), neither dropped.
4. **Dead/broken (PRESERVE + FLAG, not auto-drop — features, not junk):**
   - `ai_marketplace_moderations` (`Ai::MarketplaceModeration`) — referenced only by its own model →
     dead-code DROP candidate (needs user OK; renamed by default).
   - `ai_publisher_earnings_snapshots` — model-less + **broken**: `publisher_controller.rb:130`
     references undefined `::Ai::PublisherEarningsSnapshot` (runtime NameError). PAYMENT feature →
     user decides: complete the model, or remove the broken endpoint + drop the table.

**Maintainer decisions surfaced (4):** (a) the 4 core `ai_agent_*` tables' creation → move to core
baseline; (b) drop dead `ai_marketplace_moderations`? (c) publisher-earnings: complete vs remove
(payment, broken); (d) delete vestigial `app_` prefix (clear — will do).

## 6. Billing consolidation (Decisions 3 + "no-defer payment fixes")
User directive 2026-06-20: NOT live yet → do **not** defer payment/billing fixes. Candidate clusters:
platform `subscriptions`/`plans`/`payments`, `ai_credit_*`, `baas_subscriptions`, marketplace/app/mcp
subscriptions. Default: keep genuinely-distinct billing domains separate; merge only provable redundancy.
### §6a — Billing consolidation (preliminary; deep consumer analysis in Phase 6, within 0.4.0)
The "dual billing models" suspicion does NOT survive first inspection — the subscription-shaped tables
model DISTINCT billing surfaces, not duplicates:
- `subscriptions` (Billing::Subscription) = platform plan billing;
- `baas_subscriptions` (BaaS::Subscription) = an external BaaS *tenant's customers'* subscriptions
  (billing-as-a-service — different actor/domain);
- `marketplace_subscriptions` / `app_subscriptions` / `mcp_server_subscriptions` = per-listing /
  embedded-app / hosted-MCP billing surfaces;
- `ai_credit_*` = a NORMALIZED prepaid-credit + usage-metering system (pack=product, purchase=txn,
  transaction=ledger, usage_rate=pricing) — complementary to recurring subscriptions, not a duplicate.

**Preliminary verdict: keep separate** (merging would couple unrelated billing contexts). Phase 6 does
the deep consumer-level confirmation (services/controllers); per the no-defer directive, any genuine
redundancy found is fixed **in 0.4.0**, not punted. Likely outcome: Phase 6 is a documentation pass,
not a destructive merge. (Real-money domain → keep-separate is the correct default absent proof of
redundancy.)

## 7. Column pruning (Decision 3) — PENDING null-column scan
Targeted scan of populated tables for always-NULL / leftover columns (purged-feature debris). To be
produced as an explicit reviewed list before any column-drop migration (no column dropped without
sign-off; column drops are their own migrations, never bundled). Pre-cleared: `ai_dag_executions`,
`knowledge_base_workflows`, `workflow_*` (live — keep).

## 8. Foundational-data manifest (Decision 7 — drives Phase 9 ETL)
**MIGRATE (real data + secrets; preserve UUIDs; encrypted cols as ciphertext):**
- *Platform knowledge* (the bulk): `ai_knowledge_graph_nodes` (~108k), `ai_knowledge_graph_edges`
  (~98k), `ai_compound_learnings` (~12k), `ai_shared_knowledges` (~6.5k), `ai_skills` (139) + skill
  conflicts, `ai_data_sources` (13) + config, `ai_memory_pools` (15), `knowledge_base_articles` (90)
  + categories.
- *Connections/secrets*: `ai_providers` (6) + `ai_provider_credentials` (trace where keys live —
  encrypted col vs Vault), `file_storages` (37), `oauth_applications` (16) + Doorkeeper tokens/grants,
  `system_providers` (28) + `system_provider_credentials` (4) + regions/instance_types/zones,
  `system_acme_dns_credentials` (1), `system_bootstrap_tokens` (17), `sdwan_membership_credentials`
  (50), `git_provider*`/`devops_*_credentials`/`webhook_endpoints` where populated, `security_secrets`.
- *Identity* (real, non-test only): `accounts` (35 — FILTER demo/test), `users` (15 — filter test),
  `workers` (6), `user_roles`/`worker_roles` (re-link by role NAME), `site_settings`, flipper state.

**RESEED (do NOT migrate — regenerated):** `permissions`, `roles`, `role_permissions`, `pages`,
demo agents/teams/skills templates.

**SKIP (transient/demo):** all `trading_*` (~38k rows incl. `trading_strategies` 36,545 +
`trading_portfolios` 2,188 — experimental, not foundational), audit logs, execution traces, sessions,
notifications, jobs/queue, usage events, demo agents/conversations/tasks/goals.

> Phase 9 detail: provider/credential secret STORAGE location must be confirmed (encrypted columns
> travel via shared `master.key`; Vault refs travel via shared Vault). `accounts`/`users` need a
> real-vs-test filter (cypress seeds create test users — exclude by known test emails/subdomains).

## 9. Trading (disabled) note
36 `trading_*` tables, trading DISABLED in `config/extensions_state.json`. In the clean install
(private + disabled) they are **not created**. Live data (`trading_strategies` 36,545,
`trading_portfolios` 2,188) is **skipped** by the curated migration. To work on trading later,
re-enable + its baseline runs in full mode.

## Action lists (for Phase 4/6/9 — applied on clean rig only)
- **DROP tables (1 clear):** `cookie_consents` (core, 0 rows, no model, no refs).
  **Flagged drop-candidates (need user OK — features, not junk):** `ai_marketplace_moderations`
  (dead model), `ai_publisher_earnings_snapshots` (model-less + broken payment endpoint). Preserved
  (renamed) by default until decided.
- **DROP indexes:** ~36 redundant `idx_*`/`index_*` twins (keep one each); KEEP the 6 distinct above.
- **RENAME:** business 58 → `business_*` (see §5a); `sdwan_*` 27 → `system_sdwan_*`.
- **PK default:** all → `uuidv7()`.
- **COLUMN prune:** pending null-scan (§7).
- **CONSOLIDATE billing:** per §6a (not deferred).
