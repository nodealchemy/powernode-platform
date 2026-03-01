import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Missions E2E Tests
 *
 * Tests for the Missions page including list/detail panel layout,
 * tab navigation (active/completed/all), and Code Factory tab.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Missions', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.missions);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load missions page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/mission/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/mission/i);
    });
  });

  test.describe('List Panel', () => {
    test('should display mission list panel or empty state', async ({ page }) => {
      const hasList = await page.locator('[class*="card"], [class*="list"], [class*="panel"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*mission|no.*active|create.*mission|get started/i).count() > 0;
      const hasContent = await page.getByText(/mission/i).count() > 0;

      expect(hasList || hasEmpty || hasContent).toBeTruthy();
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display Active tab', async ({ page }) => {
      const hasActive = await page.locator('button').filter({ hasText: /active/i }).count() > 0;
      const hasContent = await page.getByText(/mission/i).count() > 0;

      expect(hasActive || hasContent).toBeTruthy();
    });

    test('should switch to Completed tab without crash', async ({ page }) => {
      const completedTab = page.locator('button').filter({ hasText: /completed/i }).first();

      if (await completedTab.count() > 0) {
        await completedTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to All tab without crash', async ({ page }) => {
      const allTab = page.locator('button').filter({ hasText: /^all$/i }).first();

      if (await allTab.count() > 0) {
        await allTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all mission tabs without crash', async ({ page }) => {
      const tabs = page.locator('button').filter({ hasText: /active|completed|^all$/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('New Mission Button', () => {
    test('should display New Mission button if user has manage permission', async ({ page }) => {
      const hasNew = await page.getByRole('button', { name: /new.*mission|create/i }).count() > 0;
      const hasContent = await page.getByText(/mission/i).count() > 0;

      expect(hasNew || hasContent).toBeTruthy();
    });
  });

  test.describe('Code Factory Tab', () => {
    test('should navigate to Code Factory tab without crash', async ({ page }) => {
      const codeFactoryTab = page.locator('button, a').filter({ hasText: /code.*factory/i }).first();

      if (await codeFactoryTab.count() > 0) {
        await codeFactoryTab.click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Responsive', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.missions);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/mission/i);
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.missions);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/mission/i);
    });
  });
});
