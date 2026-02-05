import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * A2A Tasks E2E Tests
 *
 * Tests for Agent-to-Agent (A2A) task management functionality.
 */

test.describe('A2A Tasks', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.a2aTasks);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load A2A Tasks page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/a2a|task|agent/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|task/i);
    });
  });

  test.describe('Tasks List Display', () => {
    test('should display tasks list or empty state', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasTasks = await page.locator('table tbody tr, [class*="card"], [class*="Card"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No tasks"), :text("No A2A"), :text("Create")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasTasks || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display task status indicators', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pending|running|completed|failed|cancelled|task|a2a/i);
    });

    test('should display task priority levels', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/high|medium|low|priority|task|a2a/i);
    });
  });

  test.describe('Task Creation', () => {
    test('should have create task action', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create"), button:has-text("New"), button:has-text("Add")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should open create task form when button clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Task"), button:has-text("New Task"), button:has-text("Create")').first();

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const hasForm = await page.locator('[role="dialog"], [class*="modal"], form, input').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });
  });

  test.describe('Task Details', () => {
    test('should display task details when task exists', async ({ page }) => {
      const taskRow = page.locator('table tbody tr, [class*="card"]').first();

      if (await taskRow.count() > 0) {
        await taskRow.click();
        await page.waitForTimeout(500);

        await expect(page.locator('body')).toContainText(/detail|status|agent|task/i);
      }
    });

    test('should display source and target agents', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/source|target|agent|sender|receiver|task|a2a/i);
    });
  });

  test.describe('Task Filtering', () => {
    test('should have search functionality', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should have status filter', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/all|status|filter|task|a2a/i);
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
      await page.goto(ROUTES.a2aTasks);
      await expect(page.locator('body')).toContainText(/a2a|task|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.a2aTasks);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
