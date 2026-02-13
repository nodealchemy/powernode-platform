import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Execution E2E Tests
 *
 * Tests for the ExecutionPage tabbed interface including
 * Ralph Loops, A2A Tasks, Parallel Execution, Resources, and AG-UI tabs.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Execution', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.execution);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load execution page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/execution|ralph|a2a|parallel/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/execution/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation', async ({ page }) => {
      const hasRalph = await page.getByText(/ralph/i).count() > 0;
      const hasA2a = await page.getByText(/a2a/i).count() > 0;
      const hasParallel = await page.getByText(/parallel/i).count() > 0;
      const hasExecution = await page.getByText(/execution/i).count() > 0;

      expect(hasRalph || hasA2a || hasParallel || hasExecution).toBeTruthy();
    });

    test('should switch to A2A Tasks tab without crash', async ({ page }) => {
      const a2aTab = page.locator('button').filter({ hasText: /a2a/i }).first();

      if (await a2aTab.count() > 0) {
        await a2aTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Parallel Execution tab without crash', async ({ page }) => {
      const parallelTab = page.locator('button').filter({ hasText: /parallel/i }).first();

      if (await parallelTab.count() > 0) {
        await parallelTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Resources tab without crash', async ({ page }) => {
      const resourcesTab = page.locator('button').filter({ hasText: /resource/i }).first();

      if (await resourcesTab.count() > 0) {
        await resourcesTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to AG-UI tab without crash', async ({ page }) => {
      const aguiTab = page.locator('button').filter({ hasText: /ag.?ui/i }).first();

      if (await aguiTab.count() > 0) {
        await aguiTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all tabs without crash', async ({ page }) => {
      const tabs = page.locator('[role="tablist"] button, nav button').filter({ hasText: /ralph|a2a|parallel|resource|ag.?ui/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Content Display', () => {
    test('should display content or empty state per tab', async ({ page }) => {
      const hasContent = await page.locator('[class*="card"], tr, [class*="list"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*data|empty|get started|no.*loop|no.*task/i).count() > 0;
      const hasPageContent = await page.getByText(/execution/i).count() > 0;

      expect(hasContent || hasEmpty || hasPageContent).toBeTruthy();
    });
  });
});
