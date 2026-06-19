# dev-ui-smoke — loop workload

One iteration of the UI-error-detection loop. Drives the headless route crawler,
turns its findings into improvement offers, and (in fix mode) lands the fixes.

## Iteration

1. **Crawl.** Run the crawler (the dev admin password must be in the environment
   as `UI_SMOKE_PASSWORD`; do NOT hardcode or echo it):
   ```bash
   node scripts/ui-smoke/crawl.mjs --json /tmp/ui-smoke.json --md /tmp/ui-smoke.md
   ```
   Read `/tmp/ui-smoke.json` (summary + findings).

2. **Triage → file offers.** For each `critical`/`high` finding (and notable
   `medium`s), `platform.create_improvement`:
   - `recommendation_type`: `code_lint` (frontend crash/console) or note the backend repo for a 5xx.
   - `fingerprint`: `ui-smoke|<route>|<error-kind>` (stable; idempotent re-runs update).
   - `title`/`description`/`verifier_evidence`: the route, the error text, the HTTP status, and the crawl timestamp.
   - Tag the right target: a backend 5xx whose handler lives in `server/` vs an extension; a frontend crash by its file. Private-extension findings auto-tag (gate #9).
   Skip findings already covered by an open offer (same fingerprint → deduped).

3. **Fix mode (optional).** If invoked to fix rather than discover: pick the
   top-severity open `ui-smoke|*` offer, reproduce locally, write a failing
   test/repro, fix at the root cause, verify (`tsc`/jest for frontend, RSpec for
   backend, and re-run the crawler for that one route), then commit on the loop
   branch and `platform.dev_complete_task`.

## Guardrails

- Read-only crawl against the running dev app — it only navigates and observes; it never mutates.
- Never print/commit `UI_SMOKE_PASSWORD`.
- Submodule discipline for extension fixes (commit inside the submodule first).
- Stop & report after 3 failed attempts at the same fix (CLAUDE.md hard rule).
- One finding fixed per fix-iteration — do not batch.
