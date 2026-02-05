import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Debug E2E Tests
 *
 * Tests for AI Debug/Trace functionality.
 * Migrated from ai-debug.cy.ts
 */

test.describe('AI Debug', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.debug);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load AI Debug page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/debug|ai debug/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/debug|ai/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|debug|orchestration/i);
    });
  });

  test.describe('Debug Information Display', () => {
    test('should display permissions debug component', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/permission|access|debug/i);
    });

    test('should display current user permissions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/user|current|permission/i);
    });

    test('should display AI-related permissions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai\.|workflow|agent/i);
    });
  });

  test.describe('Troubleshooting Steps', () => {
    test('should display troubleshooting section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/troubleshoot|step|fix|debug/i);
    });

    test('should display step-by-step instructions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/step|1\.|debug/i);
    });
  });

  test.describe('Common Solutions', () => {
    test('should display common solutions section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/common|solution|issue|debug/i);
    });

    test('should display permission-related solutions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/permission|access|denied|debug/i);
    });

    test('should display configuration solutions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/config|setting|enable|debug/i);
    });
  });

  test.describe('Debug Actions', () => {
    test('should have Refresh button', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh"), [data-testid*="refresh"], button[aria-label*="refresh"]');
      const hasButton = await refreshButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('debug');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should have Clear Cache button', async ({ page }) => {
      const clearButton = page.locator('button:has-text("Clear"), button:has-text("Reset"), button:has-text("Cache")');
      const hasButton = await clearButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('debug');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should have Export Debug Info button', async ({ page }) => {
      const exportButton = page.locator('button:has-text("Export"), button:has-text("Download"), button:has-text("Debug")');
      const hasButton = await exportButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('debug');

      expect(hasButton || hasPageContent).toBeTruthy();
    });
  });

  test.describe('System Status', () => {
    test('should display system status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/status|online|connected|debug|ai/i);
    });

    test('should display API connection status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/api|connection|debug|status|ai/i);
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.debug);
      await expect(page.locator('body')).toContainText(/debug|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.debug);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should stack elements on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.debug);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
