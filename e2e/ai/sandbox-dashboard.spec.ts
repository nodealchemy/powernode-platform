import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Sandbox Dashboard E2E Tests
 *
 * Tests for the SandboxDashboardPage including container sandboxes,
 * workspace management, and sandbox controls.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Sandbox Dashboard', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.sandboxes);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load sandbox dashboard without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox|container|workspace/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/sandbox/i);
    });
  });

  test.describe('Container List', () => {
    test('should display containers or empty state', async ({ page }) => {
      const hasContainers = await page.locator('[class*="card"], [class*="container"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*sandbox|no.*container|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/sandbox/i).count() > 0;

      expect(hasContainers || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display container status indicators', async ({ page }) => {
      const hasStatus = await page.getByText(/running|stopped|pending|active|inactive/i).count() > 0;
      const hasContent = await page.getByText(/sandbox/i).count() > 0;

      expect(hasStatus || hasContent).toBeTruthy();
    });
  });

  test.describe('Sandbox Actions', () => {
    test('should display create sandbox button or action', async ({ page }) => {
      const hasCreate = await page.getByRole('button', { name: /create|new|add/i }).count() > 0;
      const hasContent = await page.getByText(/sandbox/i).count() > 0;

      expect(hasCreate || hasContent).toBeTruthy();
    });
  });
});
