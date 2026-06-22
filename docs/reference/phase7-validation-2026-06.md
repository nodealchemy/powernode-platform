# Phase 7 — Full Validation Results (0.4.0 DB refactor)

**Date:** 2026-06-22 · **Branch:** `feature/db-refactor-040` · **Rig:** `/opt/powernode-clean` (live `/opt/powernode` untouched)

Gate status: **3 of 5 green**; RSpec + smokes pending (privileged test-DB setup required).

## Gate 1 — Leak guard (`scripts/pattern-validation.sh`) ✅ PASS
0 private-extension table refs in the public `schema.rb`. **Fixed 2 defects in the validation tooling
itself** (committed change to `pattern-validation.sh`):
- **Leak guard always-FAIL bug**: `leak_count=$(grep -cE ... || echo 0)` double-emitted `0` (grep -c
  prints the count *and* exits 1 on zero matches, so `|| echo 0` also fired) → multiline value broke the
  `-eq` test under `set -e` → permanent false FAIL. Fixed to `|| true` + `${leak_count:-0}`.
- **UUID-PK check stale**: tested for the obsolete `string :id, limit: 36` string-PK anti-pattern (now 0
  after the squash) → false FAIL. Re-pointed to the new convention `grep -rh 'id: :uuid' db/migrate/`
  (270 hits). Whole adherence scan now has 0 failing checks.

## Gate 2 — Schema parity vs pre-040 baseline ✅ PASS
Method: extract table sets from `baseline_clean_schema.sql` (517, old names) and the reassembled new
schema (`schema.rb` 418 + business baseline 58 + trading baseline 36 = 512); apply the 84-row
`rename_map.tsv`; diff. **Every delta is intended — zero unexpected drops or additions:**

| Δ | Table | Why intended |
|---|---|---|
| rename | `ai_publisher_earnings_snapshots` → `business_publisher_earnings_snapshots` | completed publisher-earnings payment feature (rename predates the tsv) |
| drop | `business_marketplace_moderations` | dead-code drop (rename-map target row is stale) |
| drop | `cookie_consents` | orphan junk |
| drop | `permissions` | catalog is source of truth; Permission table removed in the perms refactor |

Arithmetic closes exactly: 515 (renamed, ex Rails-internal) − 3 intended drops = 512 = new schema.
Rename-map cross-check: all 84 sources present in baseline; 83/84 targets present in new schema (the 1
absent = the intended dead-code drop). Two independent methods agree. Repro: `/tmp/p7_parity.rb`.

## Gate 3 — `zeitwerk:check` both modes ✅ PASS
- Core mode (`Gemfile`, private off): "all is good!" (exit 0)
- Full mode (`Gemfile.private`, private on, trading disabled): "all is good!" (exit 0)
- Only note (both): advisory that `extensions/system/server/lib` isn't eager-loaded — pre-existing, not a failure.

## Gate 4 — RSpec core + private ⏳ PENDING
- Test DB `powernode_clean_test` exists but is **empty**; `database.yml` test entry is isolated
  (`powernode_clean_test<%= ENV['TEST_ENV_NUMBER'] %>`), `rails_helper` calls `maintain_test_schema!`.
- **Prerequisite**: `schema.rb` needs `ltree/pg_trgm/pgcrypto/vector`; the `powernode` role lacks
  superuser → a `postgres` superuser must `CREATE EXTENSION` these in `powernode_clean_test` (and a
  full-mode test DB) before schema load. Same step the dev DB required.
- Suite size: core 746 + business 30 specs. Expect some pre-existing test debt (e.g. marketplace specs,
  supply-chain worker-job specs #49) — triage schema regressions vs. known debt.
- Full mode needs a test DB built `schema:load` (core) + `migrate` (business) and care with
  `maintain_test_schema!` (it reloads from core `schema.rb`, which would drop business tables).

## Gate 5 — ai-smoke + ui-smoke @ :3010 ⏳ PENDING
Requires the rig server running on port 3010 (isolated from live :3000). Crawls routes for per-route
frontend+backend errors.
