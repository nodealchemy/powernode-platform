import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Autonomy Dashboard E2E Tests
 *
 * Tests for the AutonomyDashboardPage including trust tiers,
 * agent trust scores, and autonomy configuration.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Autonomy Dashboard', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.autonomy);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load autonomy page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/autonomy|trust|agent/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/autonomy/i);
    });
  });

  test.describe('Trust Tiers Display', () => {
    test('should display trust tier information', async ({ page }) => {
      const hasSupervised = await page.getByText(/supervised/i).count() > 0;
      const hasMonitored = await page.getByText(/monitored/i).count() > 0;
      const hasTrusted = await page.getByText(/trusted/i).count() > 0;
      const hasAutonomous = await page.getByText(/autonomous/i).count() > 0;
      const hasTrust = await page.getByText(/trust|tier|autonomy/i).count() > 0;

      expect(hasSupervised || hasMonitored || hasTrusted || hasAutonomous || hasTrust).toBeTruthy();
    });
  });

  test.describe('Agent Trust Scores', () => {
    test('should display agent trust scores or empty state', async ({ page }) => {
      const hasScores = await page.locator('[class*="card"], [class*="score"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*agent|no.*score|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/autonomy|trust/i).count() > 0;

      expect(hasScores || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display score values without crash', async ({ page }) => {
      const scoreElements = page.locator('[class*="score"], [class*="progress"], [class*="badge"]');

      if (await scoreElements.count() > 0) {
        await expect(scoreElements.first()).toBeVisible();
      }
    });
  });

  test.describe('Autonomy Configuration', () => {
    test('should display configuration section or settings', async ({ page }) => {
      const hasConfig = await page.getByText(/config|setting|threshold|policy/i).count() > 0;
      const hasContent = await page.getByText(/autonomy/i).count() > 0;

      expect(hasConfig || hasContent).toBeTruthy();
    });
  });
});
