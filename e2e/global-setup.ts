import { test as setup, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const authFile = 'e2e/.auth/user.json';

/**
 * Global setup for Playwright tests
 *
 * Authenticates a test user and stores the session for reuse across all tests.
 * The login is provisioned per run (no credentials file) — see loadTestCredentials.
 */
setup('authenticate', async ({ page }) => {
  // Ensure auth directory exists
  const authDir = path.dirname(authFile);
  if (!fs.existsSync(authDir)) {
    fs.mkdirSync(authDir, { recursive: true });
  }

  // Resolve a test login (per-run provisioned or env-supplied)
  const credentials = await loadTestCredentials();

  // Navigate to login page
  await page.goto('/login');

  // Wait for login form to be ready
  await page.waitForSelector('input[type="email"], input[name="email"]', { timeout: 30000 });

  // Fill in credentials
  await page.fill('input[type="email"], input[name="email"]', credentials.email);
  await page.fill('input[type="password"], input[name="password"]', credentials.password);

  // Submit login form
  await page.click('button[type="submit"]');

  // Wait for successful login - should redirect to dashboard or app
  await page.waitForURL(/\/(app|dashboard)/, { timeout: 30000 });

  // Verify we're logged in by checking for common authenticated UI elements
  await expect(page.locator('body')).toBeVisible();

  // Save authentication state
  await page.context().storageState({ path: authFile });
});

/**
 * Resolve a test-user login WITHOUT any credentials file on disk:
 *   1. explicit TEST_USER_EMAIL / TEST_USER_PASSWORD env (remote/CI) wins, else
 *   2. provision per-run via the real reset endpoint
 *      (scripts/e2e/provision-test-logins.cjs) and use the admin (fallback demo) login.
 */
async function loadTestCredentials(): Promise<{ email: string; password: string }> {
  if (process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD) {
    return { email: process.env.TEST_USER_EMAIL, password: process.env.TEST_USER_PASSWORD };
  }

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { provisionTestLogins } = require('../scripts/e2e/provision-test-logins.cjs');
  const logins: Record<string, { email: string; password: string }> = await provisionTestLogins();
  const chosen = logins.admin || logins.demo;
  if (!chosen) {
    throw new Error(
      'Failed to provision a test login. Ensure the backend is up and demo users are seeded ' +
        '(POWERNODE_SEED_DEMO=true rails db:seed), or set TEST_USER_EMAIL / TEST_USER_PASSWORD.',
    );
  }
  return chosen;
}
