# UI Smoke Crawler

A headless-browser route crawler — the **UI twin of `scripts/ai-smoke/`**. Where
`ai-smoke` replays the frontend's API requests against the backend, `ui-smoke`
drives a real browser through every `/app` route and catches the errors that only
surface in the page: uncaught JS exceptions, `console.error`, React error
boundaries, and the 4xx/5xx backend responses each page triggers.

It exists to make the manual "click every page and watch the console" QA pass
**automated and repeatable** (and loopable — see Dev-loop below). It would have
caught every error found by hand: the marketplace 500, the BaaS 401 storm, the
Cost/ROI sparse-data crashes, the badge issues' console noise.

## What it does

1. **Logs in via the UI** (`/login` → fills `email-input`/`password-input` →
   `login-submit-btn`). The access token lives in Redux (not localStorage), so a
   real login is required — credentials come from env.
2. **BFS-crawls** `/app` routes, discovering links (including tabs) as it visits.
3. **Per route captures:** `pageerror` (uncaught JS), `console.error`, and every
   HTTP response with status ≥ 400 (the backend errors).
4. **Writes a severity-ranked report** (`last-report.md` + `.json`):
   `critical` (any 5xx) > `high` (uncaught JS) > `medium` (4xx) > `low` (console).
   Exits non-zero if any critical/high.

Tolerable noise (favicon, ResizeObserver, the expected BaaS-no-tenant 401, …) is
filtered — edit the `IGNORE` list in `crawl.mjs` to tune.

## Run

```bash
# browsers are already cached (~/.cache/ms-playwright); @playwright/test is a
# frontend/ devDependency.
UI_SMOKE_PASSWORD='<dev admin password>' node scripts/ui-smoke/crawl.mjs

# options
UI_SMOKE_BASE_URL=https://dev.powernode.org \   # default; or http://localhost:3001 (vite)
UI_SMOKE_EMAIL=admin@powernode.org \            # default
UI_SMOKE_PASSWORD=... \
  node scripts/ui-smoke/crawl.mjs --max 150 --timeout 20000 --md /tmp/ui-smoke.md
```

`UI_SMOKE_PASSWORD` is the only required input (we can't mint a browser session
the way `ai-smoke` mints a JWT — the token is Redux-only).

## Dev-loop (`dev-ui-smoke`)

`PROMPT.md` is the loop workload: an iteration runs the crawler, reads the report,
files a `create_improvement` offer per new critical/high finding (fingerprint
`ui-smoke|<route>|<error-kind>`), and — in fix iterations — drives the offer to a
verified fix via `/dev-loop`. Register it as a `claude_code` Ralph loop pointing
`loop_spec_path` at this `PROMPT.md`, or run the crawler on a cron and let the
findings flow into the improvement lane like `ai-smoke`'s do.
