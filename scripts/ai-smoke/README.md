# AI Frontend-Actions Smoke Harness

A dependency-free Node harness that replays the requests the React frontend makes
against every core AI domain, classifies the responses, and writes a
severity-ranked findings report. It is the engine for the **discover → fix →
re-test** loop on AI frontend actions.

## Why this exists

The frontend talks to ~300 AI endpoints across 15 domains. Bugs in that surface
(contract mismatches, 500s, un-editable records) show up in the browser but are
usually backend defects. This harness exercises that surface from the outside —
no stubs — so it catches interface drift that fully-green unit specs miss
(stubbing a collaborator hides the drift; a live call cannot).

## Safety model (important — local == dev.powernode.org)

On this deployment the running server **is** the dev environment, so mutating
calls hit real data. The harness is non-destructive by construction:

- **Reads** of pre-existing records (lists, show/detail, stats) — always safe.
- **Sample**: pulls the first id from each list and exercises its detail +
  read sub-resources. Reads only; skipped when a list is empty.
- **Write lifecycle**: full `create → exercise → delete` ONLY on fixtures the
  harness creates, named `smoketest-<runId>-*`. It never updates or deletes a
  record it did not create.
- **External side-effect actions** (`test_connection`, `sync_models`, agent
  `execute`, …) hit real LLMs/providers (cost + side effects) and are **not**
  run by the default runner — they are catalogued in the manifest for reference.

## Usage

```bash
# READ sweep across all domains (safe, default)
node scripts/ai-smoke/run.mjs

# READ + WRITE lifecycle (creates/deletes namespaced fixtures)
node scripts/ai-smoke/run.mjs --phase all

# Target specific domains
node scripts/ai-smoke/run.mjs --phase all --domain providers,agents

# Keep created fixtures for inspection (skips deletion)
node scripts/ai-smoke/run.mjs --phase write --domain providers --no-cleanup
```

Flags: `--phase read|write|all` (default `read`) · `--domain a,b,c` ·
`--base-url URL` (default `http://localhost:3000/api/v1`) · `--user EMAIL`
(default `admin@powernode.org`) · `--no-cleanup` · `--timeout MS` ·
`--md PATH` · `--json PATH` · `--quiet`.

Exit code = number of findings (0 = clean), so it drops into CI / `&&` chains.

## Authentication

Precedence:

1. `AI_SMOKE_TOKEN` env var — use a token you already hold.
2. Otherwise the harness mints a short-lived JWT via
   `bundle exec rails runner mint_token.rb` for a seeded user
   (`AI_SMOKE_USER`, default `admin@powernode.org`).

This avoids the stale-password problem of `test-credentials.json` (regenerated on
every `db:seed`) and mirrors how `scripts/mcp-smoke-test.sh` authenticates. The
token is held in memory only and is **never** written to logs or the report.

## Output

- `docs/operations/ai-smoke-findings.md` — human-readable, grouped by severity.
- `docs/operations/ai-smoke-findings.json` — machine-readable for diffing runs.

Severity heuristics: `critical` (5xx / network), `high` (422/400/409 on a
controlled-valid request), `investigate` (404 — missing fixture **or** a route
not mounted in this checkout, e.g. extension-gated features), `auth` (401/403),
`medium` (other non-2xx).

## Extending the manifest

`manifest.mjs` is the catalog. To add coverage, add entries under a domain:

- `read[]` — `{ id, method, path, expect? }` for no-id collection endpoints.
- `sample` — `{ listPath, steps: (id) => [...] }` to exercise a real record.
- `lifecycle` — `{ create, steps: (id) => [...], destroy }` for owned fixtures.
  `create.body` must mirror the **exact** wrapper key the frontend sends
  (e.g. `{ provider: {...} }`), and `create.idPath` is the path to the new id in
  the response (e.g. `['provider', 'id']`).

WRITE lifecycles are currently populated for `providers` (which also regression-
guards the `supported_models` edit fix). Agents/teams/conversations write
lifecycles are the next extension point — each needs its create payload mapped
from the corresponding create form + controller permit list.

## Browser layer (Playwright)

The API harness catches backend contract bugs; the render/JS-error layer is
covered by `e2e/ai/ai-smoke.spec.ts`. It reuses the existing `e2e/pages/ai/*`
page objects and asserts each key AI page (providers, agents, conversations, and
the analytics/monitoring/governance/teams dashboards) renders with **no uncaught
JS errors**. It authenticates by injecting a freshly-minted refresh-token cookie
(same JWT approach as `auth.mjs`), so it does not depend on the stale
`test-credentials.json` password login in `e2e/global-setup.ts`.

```bash
# frontend must be running on :3001, backend on :3000
npx playwright test e2e/ai/ai-smoke.spec.ts --project=chromium --no-deps
```

`--no-deps` skips the `setup` project (the stale-password global-setup); the spec
self-authenticates.

## Running it as a loop

- Ad hoc: re-run after each fix; diff `ai-smoke-findings.json` between runs.
- Scheduled regression guard: `/loop 1h node scripts/ai-smoke/run.mjs` (or wire
  into CI). The non-zero exit on findings makes it a usable gate.

## Notes

- The abandoned plugin-marketplace feature (frontend `PluginsApiService`, no
  backend) was removed; it is intentionally not in the manifest.
