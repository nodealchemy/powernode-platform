import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Evaluation Dashboard E2E Tests
 *
 * Tests for the EvaluationDashboardPage including evaluation results,
 * benchmarks, and agent comparison sections.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Evaluation Dashboard', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.evaluation);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load evaluation page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/evaluat|benchmark|comparison/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/evaluat/i);
    });
  });

  test.describe('Evaluation Results Tab', () => {
    test('should display evaluation results or empty state', async ({ page }) => {
      const hasResults = await page.locator('[class*="card"], [class*="result"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*result|no.*evaluat|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/evaluat/i).count() > 0;

      expect(hasResults || hasEmpty || hasContent).toBeTruthy();
    });
  });

  test.describe('Benchmarks Tab', () => {
    test('should switch to benchmarks tab without crash', async ({ page }) => {
      const benchmarksTab = page.locator('button').filter({ hasText: /benchmark/i }).first();

      if (await benchmarksTab.count() > 0) {
        await benchmarksTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should display benchmark data or empty state', async ({ page }) => {
      const benchmarksTab = page.locator('button').filter({ hasText: /benchmark/i }).first();

      if (await benchmarksTab.count() > 0) {
        await benchmarksTab.click();
        await page.waitForTimeout(500);

        const hasBenchmarks = await page.locator('[class*="card"], [class*="benchmark"], tr').count() > 0;
        const hasEmpty = await page.getByText(/no.*benchmark|empty|no data/i).count() > 0;
        const hasContent = await page.getByText(/benchmark|evaluat/i).count() > 0;

        expect(hasBenchmarks || hasEmpty || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Agent Comparison Tab', () => {
    test('should switch to agent comparison tab without crash', async ({ page }) => {
      const comparisonTab = page.locator('button').filter({ hasText: /comparison|compare/i }).first();

      if (await comparisonTab.count() > 0) {
        await comparisonTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should display comparison data or empty state', async ({ page }) => {
      const comparisonTab = page.locator('button').filter({ hasText: /comparison|compare/i }).first();

      if (await comparisonTab.count() > 0) {
        await comparisonTab.click();
        await page.waitForTimeout(500);

        const hasComparison = await page.locator('[class*="card"], [class*="chart"], canvas, svg').count() > 0;
        const hasEmpty = await page.getByText(/no.*agent|select.*agent|empty|no data/i).count() > 0;
        const hasContent = await page.getByText(/comparison|compare|evaluat/i).count() > 0;

        expect(hasComparison || hasEmpty || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Tab Cycling', () => {
    test('should cycle through all tabs without crash', async ({ page }) => {
      const tabs = page.locator('[role="tablist"] button, nav button').filter({ hasText: /result|benchmark|comparison|compare/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });
});
