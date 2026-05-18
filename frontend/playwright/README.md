# Playwright cross-browser smoke

This directory holds Playwright specs that run against Chromium, Firefox, and WebKit.

**Cypress remains the primary E2E suite** for deep functional testing. Playwright lives alongside it to catch cross-browser regressions that Chromium-only Cypress can't see.

## One-time setup

```bash
npm install --save-dev @playwright/test
npx playwright install   # downloads ~200MB of browser binaries — once per machine
```

Playwright is intentionally not a hard dependency of the frontend `package.json` — adding it forces every contributor to download the browser binaries. Install it locally when you need to run these specs.

## Run

```bash
# Run all browsers
npx playwright test

# Run a single browser
npx playwright test --project=chromium
npx playwright test --project=firefox
npx playwright test --project=webkit

# Watch mode + UI
npx playwright test --ui

# Generate an HTML report
npx playwright test --reporter=html
npx playwright show-report
```

## Configuration

See `frontend/playwright.config.ts`. The dev server is started automatically when tests run; set `PLAYWRIGHT_BASE_URL=...` to point at an already-running instance.

## Adding tests

- Keep this suite **shallow** — 1-2 tests per page at most.
- Use existing Cypress tests (`frontend/cypress/e2e/`) for deep behavior.
- Reach for Playwright only when the regression is browser-specific (Firefox CSS issue, WebKit safari quirk, etc.).
- Name files `<page-or-feature>.spec.ts` directly in this directory.

## CI

Not wired into CI yet. To enable, add a workflow job that runs:

```yaml
- run: npm install --save-dev @playwright/test
- run: npx playwright install --with-deps
- run: npx playwright test --reporter=line
```

Allow ~5 minutes for the browser binary install on first run; cache `~/.cache/ms-playwright` to speed subsequent runs.
