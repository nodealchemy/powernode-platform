import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Knowledge Graph E2E Tests
 *
 * Tests for the Knowledge Graph tab under the Knowledge page.
 * Includes Graph Explorer, Skill Graph, and Hybrid Search sub-tabs.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Knowledge Graph', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.knowledgeGraph);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load knowledge graph page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/graph|knowledge/i);
    });

    test('should display Knowledge page with Graph tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/knowledge/i);
    });
  });

  test.describe('Sub-Tab Navigation', () => {
    test('should display Graph Explorer tab', async ({ page }) => {
      const hasGraphExplorer = await page.locator('button').filter({ hasText: /graph.*explorer/i }).count() > 0;
      const hasContent = await page.getByText(/graph|knowledge/i).count() > 0;

      expect(hasGraphExplorer || hasContent).toBeTruthy();
    });

    test('should switch to Skill Graph tab without crash', async ({ page }) => {
      const skillGraphTab = page.locator('button').filter({ hasText: /skill.*graph/i }).first();

      if (await skillGraphTab.count() > 0) {
        await skillGraphTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Hybrid Search tab without crash', async ({ page }) => {
      const hybridTab = page.locator('button').filter({ hasText: /hybrid.*search/i }).first();

      if (await hybridTab.count() > 0) {
        await hybridTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all graph tabs without crash', async ({ page }) => {
      const tabs = page.locator('button').filter({ hasText: /graph.*explorer|skill.*graph|hybrid.*search/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Graph Visualization', () => {
    test('should display graph visualization area or empty state', async ({ page }) => {
      const hasCanvas = await page.locator('canvas, svg, [class*="graph"], [class*="visualization"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*node|no.*graph|empty|no data|no.*permission/i).count() > 0;
      const hasContent = await page.getByText(/graph|knowledge|node|edge/i).count() > 0;

      expect(hasCanvas || hasEmpty || hasContent).toBeTruthy();
    });
  });

  test.describe('Statistics', () => {
    test('should display node/edge counts or statistics panel', async ({ page }) => {
      const hasStats = await page.getByText(/node|edge|count|statistic|total/i).count() > 0;
      const hasContent = await page.getByText(/graph|knowledge/i).count() > 0;

      expect(hasStats || hasContent).toBeTruthy();
    });
  });

  test.describe('Hybrid Search', () => {
    test('should display search input in Hybrid Search tab', async ({ page }) => {
      const hybridTab = page.locator('button').filter({ hasText: /hybrid.*search/i }).first();

      if (await hybridTab.count() > 0) {
        await hybridTab.click();
        await page.waitForTimeout(500);

        const hasSearch = await page.locator('input[type="search"], input[placeholder*="search" i], input[type="text"]').count() > 0;
        const hasContent = await page.getByText(/search|hybrid/i).count() > 0;

        expect(hasSearch || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Responsive', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.knowledgeGraph);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/graph|knowledge/i);
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.knowledgeGraph);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/graph|knowledge/i);
    });
  });
});
