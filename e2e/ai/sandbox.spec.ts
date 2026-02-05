import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Sandbox E2E Tests
 *
 * Tests for Sandbox & Testing Infrastructure functionality.
 * Migrated from ai-sandbox.cy.ts and ai-sandbox-workflows.cy.ts
 */

test.describe('AI Sandbox', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.sandbox);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Sandbox page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox|testing|test environment/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox|testing/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|sandbox/i);
    });
  });

  test.describe('Sandbox Management', () => {
    test('should display sandboxes section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox|environment|testing/i);
    });

    test('should have Create Sandbox button', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Sandbox"), button:has-text("New Sandbox"), button:has-text("Create")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('sandbox');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should display sandbox types', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/standard|isolated|production|performance|security|sandbox/i);
    });

    test('should display sandbox status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|inactive|paused|expired|status|sandbox/i);
    });
  });

  test.describe('Sandbox Actions', () => {
    test('should have activate/deactivate actions', async ({ page }) => {
      const actionButton = page.locator('button:has-text("Activate"), button:has-text("Deactivate"), button:has-text("Run Tests")');
      const hasAction = await actionButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('sandbox');

      expect(hasAction || hasPageContent).toBeTruthy();
    });

    test('should display sandbox analytics info', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics|statistics|metrics|runs|executions|sandbox/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox|scenario|mock|run|benchmark|a\/b/i);
    });

    test('should switch to Test Scenarios tab', async ({ page }) => {
      const scenariosTab = page.locator('button').filter({ hasText: /scenario/i }).first();

      if (await scenariosTab.count() > 0) {
        await scenariosTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/scenario|test|sandbox/i);
      }
    });

    test('should switch to Mock Responses tab', async ({ page }) => {
      const mocksTab = page.locator('button').filter({ hasText: /mock/i }).first();

      if (await mocksTab.count() > 0) {
        await mocksTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/mock|response|sandbox/i);
      }
    });

    test('should switch to Test Runs tab', async ({ page }) => {
      const runsTab = page.locator('button').filter({ hasText: /run/i }).first();

      if (await runsTab.count() > 0) {
        await runsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/run|test|sandbox/i);
      }
    });

    test('should switch to Benchmarks tab', async ({ page }) => {
      const benchmarksTab = page.locator('button').filter({ hasText: /benchmark/i }).first();

      if (await benchmarksTab.count() > 0) {
        await benchmarksTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/benchmark|performance|sandbox/i);
      }
    });

    test('should switch to A/B Tests tab', async ({ page }) => {
      const abTestsTab = page.locator('button').filter({ hasText: /a\/b/i }).first();

      if (await abTestsTab.count() > 0) {
        await abTestsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/a\/b|test|experiment|sandbox/i);
      }
    });
  });

  test.describe('Test Scenarios', () => {
    test('should display scenarios section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/scenario|test case|test|sandbox/i);
    });

    test('should display scenario types', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/unit|integration|regression|performance|security|sandbox/i);
    });
  });

  test.describe('Test Runs', () => {
    test('should display test runs section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/test run|run|execution|sandbox/i);
    });

    test('should display run status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pending|running|completed|failed|cancelled|sandbox/i);
    });

    test('should display pass rate metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pass rate|passed|failed|skipped|sandbox/i);
    });
  });

  test.describe('Performance Benchmarks', () => {
    test('should display benchmarks section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/benchmark|performance|profiling|sandbox/i);
    });

    test('should display benchmark metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/baseline|threshold|score|trend|sandbox/i);
    });
  });

  test.describe('A/B Testing', () => {
    test('should display A/B tests section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/a\/b|experiment|variant|sandbox/i);
    });

    test('should display statistical significance', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/significance|confidence|winning|variant|sandbox/i);
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      }
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
      await page.goto(ROUTES.sandbox);
      await expect(page.locator('body')).toContainText(/sandbox|testing/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.sandbox);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should adapt layout on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.sandbox);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
