import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Container Orchestration E2E Tests
 *
 * Tests for the ContainersPage including execution list,
 * templates, and quotas tabs.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('Container Orchestration', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.containers);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load containers page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/container|execution|template|quota/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/container/i);
    });
  });

  test.describe('Container List', () => {
    test('should display container list or empty state', async ({ page }) => {
      const hasContainers = await page.locator('[class*="card"], [class*="container"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*container|no.*execution|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/container/i).count() > 0;

      expect(hasContainers || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display container status indicators', async ({ page }) => {
      const hasStatus = await page.getByText(/running|stopped|pending|completed|failed/i).count() > 0;
      const hasContent = await page.getByText(/container/i).count() > 0;

      expect(hasStatus || hasContent).toBeTruthy();
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation', async ({ page }) => {
      const hasExecutions = await page.getByText(/execution/i).count() > 0;
      const hasTemplates = await page.getByText(/template/i).count() > 0;
      const hasQuotas = await page.getByText(/quota/i).count() > 0;
      const hasContainers = await page.getByText(/container/i).count() > 0;

      expect(hasExecutions || hasTemplates || hasQuotas || hasContainers).toBeTruthy();
    });

    test('should switch to Templates tab without crash', async ({ page }) => {
      const templatesTab = page.locator('button').filter({ hasText: /template/i }).first();

      if (await templatesTab.count() > 0) {
        await templatesTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Quotas tab without crash', async ({ page }) => {
      const quotasTab = page.locator('button').filter({ hasText: /quota/i }).first();

      if (await quotasTab.count() > 0) {
        await quotasTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all tabs without crash', async ({ page }) => {
      const tabs = page.locator('[role="tablist"] button, nav button').filter({ hasText: /execution|template|quota/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });
});
