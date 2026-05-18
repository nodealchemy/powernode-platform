import { defineConfig, devices } from '@playwright/test';

/**
 * Cross-browser smoke test config.
 *
 * Sits alongside the existing Cypress test suite — Cypress runs Chromium-only
 * for the deep functional tests; Playwright runs a small smoke surface against
 * Chromium, Firefox, and WebKit so cross-browser regressions surface quickly.
 *
 * Setup (one-time per machine):
 *   npm install --save-dev @playwright/test
 *   npx playwright install   # downloads ~200MB of browser binaries
 *
 * Run:
 *   npx playwright test                       # all browsers
 *   npx playwright test --project=chromium    # one browser
 *   npx playwright test --reporter=html       # rich UI report
 *
 * The dev server is started automatically (webServer below) when tests run.
 */
export default defineConfig({
  testDir: './playwright',
  testMatch: '**/*.spec.ts',
  timeout: 30_000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox',  use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit',   use: { ...devices['Desktop Safari'] } },
  ],

  webServer: process.env.PLAYWRIGHT_BASE_URL
    ? undefined
    : {
        command: 'npm run dev',
        url: 'http://localhost:5173',
        reuseExistingServer: !process.env.CI,
        timeout: 60_000,
      },
});
