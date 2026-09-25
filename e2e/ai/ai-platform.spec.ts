import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Platform E2E Tests
 *
 * The former Infrastructure hub became separate AI Platform pages: Providers,
 * Data Sources, Model Router, and the MCP page (Servers, Apps, Studio,
 * Sessions tabs). Uses the error-capture pattern to detect runtime crashes
 * like the Model Router toFixed bug.
 */

test.describe('AI Platform', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  const open = async (page: import('@playwright/test').Page, route: string) => {
    await page.goto(route);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 15000 });
  };

  test.describe('Providers', () => {
    test('should display providers list or empty state', async ({ page }) => {
      await open(page, ROUTES.providers);
      await expect(page.locator('body')).toContainText(/provider/i);
    });
  });

  test.describe('Data Sources', () => {
    test('should load the data sources page', async ({ page }) => {
      await open(page, ROUTES.dataSources);
      await expect(page.locator('body')).toContainText(/data source/i);
    });
  });

  test.describe('MCP', () => {
    test('should load the MCP page with its tabs', async ({ page }) => {
      await open(page, ROUTES.mcp);
      await expect(page.locator('body')).toContainText(/mcp|model context protocol/i);
    });

    test('should cycle through the MCP tabs without crash', async ({ page }) => {
      await open(page, ROUTES.mcp);
      const tabs = page.getByRole('tab');
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Model Router', () => {
    test('should load the Model Router page', async ({ page }) => {
      await open(page, ROUTES.modelRouter);
      await expect(page.locator('body')).toContainText(/model.*router|routing|rule/i);
    });

    test('should display routing rules or empty state', async ({ page }) => {
      await open(page, ROUTES.modelRouter);

      const hasRules = await page.locator('[class*="card"], [class*="rule"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*rule|no.*route|empty|get started/i).count() > 0;
      const text = (await page.locator('body').textContent())?.toLowerCase() ?? '';

      expect(hasRules || hasEmpty || text.includes('model') || text.includes('router')).toBeTruthy();
    });

    test('should expand rule card without crash (toFixed regression)', async ({ page }) => {
      await open(page, ROUTES.modelRouter);

      const ruleCard = page.locator('[class*="card"], [class*="rule"], tr').first();
      if (await ruleCard.count() > 0) {
        await ruleCard.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
        expect(pageErrors.filter(e => /toFixed|undefined|null/i.test(e))).toEqual([]);
      }
    });
  });
});
