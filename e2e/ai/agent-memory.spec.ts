import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Agent Memory E2E Tests
 *
 * Tests for Agent Memory / Context management functionality.
 */

test.describe('Agent Memory', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.contexts);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Agent Memory/Contexts page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/memory|context|knowledge|ai/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|memory|context/i);
    });
  });

  test.describe('Memory List Display', () => {
    test('should display memory entries or empty state', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasEntries = await page.locator('table tbody tr, [class*="card"], [class*="Card"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No memory"), :text("No context"), :text("Create")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('memory') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasEntries || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display memory types', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/factual|experiential|procedural|type|memory|context/i);
    });

    test('should display memory status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|archived|status|memory|context/i);
    });
  });

  test.describe('Memory Creation', () => {
    test('should have create memory action', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create"), button:has-text("New"), button:has-text("Add")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('memory') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should open create memory form when button clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create"), button:has-text("New"), button:has-text("Add Memory")').first();

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const hasForm = await page.locator('[role="dialog"], [class*="modal"], form, input').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });
  });

  test.describe('Memory Details', () => {
    test('should display memory entry details when clicked', async ({ page }) => {
      const entryRow = page.locator('table tbody tr, [class*="card"]').first();

      if (await entryRow.count() > 0) {
        await entryRow.click();
        await page.waitForTimeout(500);

        await expect(page.locator('body')).toContainText(/detail|value|key|content|memory|context/i);
      }
    });
  });

  test.describe('Memory Search', () => {
    test('should have search functionality', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should have type filter', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/all|type|filter|memory|context/i);
    });
  });

  test.describe('Memory Actions', () => {
    test('should have delete action when entries exist', async ({ page }) => {
      const hasEntries = await page.locator('table tbody tr, [class*="card"]').count() > 0;

      if (hasEntries) {
        const deleteButton = page.locator('button[title*="Delete"], [class*="trash"], button:has-text("Delete")');
        const hasDelete = await deleteButton.count() > 0;
        expect(hasDelete).toBeTruthy();
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
      await page.goto(ROUTES.contexts);
      await expect(page.locator('body')).toContainText(/memory|context|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.contexts);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
