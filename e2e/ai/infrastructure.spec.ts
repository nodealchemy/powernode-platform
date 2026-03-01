import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Infrastructure E2E Tests
 *
 * Tests for the InfrastructurePage tabbed interface including
 * Providers, MCP Servers, Model Router, and MCP Apps tabs.
 * Uses error-capture pattern to detect runtime crashes like the toFixed bug.
 */

test.describe('AI Infrastructure', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.infrastructure);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load infrastructure page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/infrastructure|provider|mcp|model/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/infrastructure/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation with expected tabs', async ({ page }) => {
      const hasProviders = await page.getByRole('button', { name: /provider/i }).or(page.locator('button:has-text("Providers")')).count() > 0;
      const hasMcp = await page.getByText(/mcp/i).count() > 0;
      const hasModelRouter = await page.getByText(/model.*router/i).count() > 0;

      expect(hasProviders || hasMcp || hasModelRouter).toBeTruthy();
    });

    test('should switch to Model Router tab without crash', async ({ page }) => {
      const modelRouterTab = page.locator('button').filter({ hasText: /model.*router/i }).first();

      if (await modelRouterTab.count() > 0) {
        await modelRouterTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to MCP tab without crash', async ({ page }) => {
      const mcpTab = page.locator('button').filter({ hasText: /^mcp$/i }).first()
        .or(page.locator('button').filter({ hasText: /mcp server/i }).first());

      if (await mcpTab.count() > 0) {
        await mcpTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to MCP Apps tab without crash', async ({ page }) => {
      const mcpAppsTab = page.locator('button').filter({ hasText: /mcp app/i }).first();

      if (await mcpAppsTab.count() > 0) {
        await mcpAppsTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all tabs without crash', async ({ page }) => {
      const tabs = page.locator('[role="tablist"] button, nav button').filter({ hasText: /provider|mcp|model|app/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Model Router', () => {
    test('should navigate to Model Router page directly', async ({ page }) => {
      await page.goto(ROUTES.modelRouter);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 15000 });
      await expect(page.locator('body')).toContainText(/model.*router|routing|rule|infrastructure/i);
    });

    test('should display routing rules or empty state', async ({ page }) => {
      await page.goto(ROUTES.modelRouter);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 15000 });

      const hasRules = await page.locator('[class*="card"], [class*="rule"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*rule|no.*route|empty|get started/i).count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('model') ||
                         (await page.locator('body').textContent())?.toLowerCase().includes('router');

      expect(hasRules || hasEmpty || hasContent).toBeTruthy();
    });

    test('should expand rule card without crash (toFixed regression)', async ({ page }) => {
      await page.goto(ROUTES.modelRouter);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 15000 });

      const ruleCard = page.locator('[class*="card"], [class*="rule"], tr').first();
      if (await ruleCard.count() > 0) {
        await ruleCard.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
        // Specifically check no toFixed-style errors
        expect(pageErrors.filter(e => /toFixed|undefined|null/i.test(e))).toEqual([]);
      }
    });
  });

  test.describe('Providers Tab', () => {
    test('should display providers list or empty state', async ({ page }) => {
      const hasProviders = await page.locator('[class*="card"], tr, [class*="provider"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*provider|add.*provider|empty/i).count() > 0;
      const hasContent = await page.getByText(/provider|infrastructure/i).count() > 0;

      expect(hasProviders || hasEmpty || hasContent).toBeTruthy();
    });
  });
});
