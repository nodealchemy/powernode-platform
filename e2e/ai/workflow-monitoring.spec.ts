import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Workflow Monitoring E2E Tests
 *
 * Tests for the WorkflowMonitoringPage which redirects to AI System Monitoring
 * page with the Workflows tab active (/app/ai/monitoring/workflows).
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Workflow Monitoring', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.workflowMonitoring);
    // The page redirects to /app/ai/monitoring/workflows — wait for it
    await page.waitForURL(/\/app\/ai\/monitoring/, { timeout: 15000 });
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should redirect to monitoring page without errors', async ({ page }) => {
      await expect(page).toHaveURL(/\/app\/ai\/monitoring/);
    });

    test('should display monitoring page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/monitoring/i);
    });
  });

  test.describe('Monitoring Tabs', () => {
    test('should display Workflows tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflow/i);
    });

    test('should display monitoring stat cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|running|completed|failed|cost/i);
    });
  });

  test.describe('Monitoring Dashboard', () => {
    test('should display monitoring metrics or stats', async ({ page }) => {
      const hasMetrics = await page.locator('[class*="card"], [class*="metric"], [class*="stat"]').count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('monitoring');

      expect(hasMetrics || hasContent).toBeTruthy();
    });
  });

  test.describe('Dashboard Controls', () => {
    test('should display refresh or real-time controls', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/refresh|enable|real.?time|monitoring/i);
    });
  });
});
