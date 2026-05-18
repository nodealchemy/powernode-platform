import { test, expect } from '@playwright/test';

/**
 * Cross-browser smoke spec.
 *
 * Goal: catch obvious cross-browser regressions (script crashes, broken
 * layout, missing fonts) within ~10s per browser. NOT a replacement for
 * the Cypress functional suite — that owns deep behavior. This catches
 * the things Cypress can't: Firefox/WebKit-specific issues.
 *
 * Add new specs at the page level (one file per page) rather than
 * extending this one beyond ~5 tests. Use existing Cypress tests for
 * deep behavior; reach for Playwright only when the regression is
 * browser-specific.
 */

test.describe('Smoke — every browser', () => {
  test('login page renders without console errors', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });

    await page.goto('/login');

    await expect(page).toHaveTitle(/Powernode|Sign in|Login/i);
    await expect(page.getByTestId('email-input')).toBeVisible();
    await expect(page.getByTestId('password-input')).toBeVisible();
    await expect(page.getByTestId('login-submit-btn')).toBeVisible();

    // Filter out tolerable warnings (favicon 404s on first load, etc).
    const fatalErrors = errors.filter(
      (e) => !e.includes('favicon') && !e.includes('Failed to load resource')
    );
    expect(fatalErrors, `page errors:\n${fatalErrors.join('\n')}`).toEqual([]);
  });

  test('plans page renders public cards', async ({ page }) => {
    await page.goto('/plans');
    // Public plan cards: either testid or the public marker exists.
    const card = page.locator('[data-testid="plan-card"], [data-public-plan-card="true"]').first();
    await expect(card).toBeVisible({ timeout: 10_000 });
  });

  test('login submit click does not throw', async ({ page }) => {
    await page.goto('/login');

    // Use intentionally-wrong credentials — we only care the submit cycle
    // completes without a JS error, not that auth succeeds.
    await page.getByTestId('email-input').fill('smoke@example.invalid');
    await page.getByTestId('password-input').fill('wrong-password');

    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));

    await page.getByTestId('login-submit-btn').click();

    // Either the page navigates (success path) or stays put with an error
    // notification (failure path). Both are valid; what we DON'T want is a
    // JS exception.
    await page.waitForTimeout(1000);
    expect(errors, `page errors:\n${errors.join('\n')}`).toEqual([]);
  });
});
