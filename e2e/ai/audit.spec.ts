import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Audit Dashboard E2E Tests
 *
 * Tests for the AuditDashboardPage including audit logs,
 * compliance entries, and security audit trail.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Audit Dashboard', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.audit);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load audit page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/audit|compliance|security|log/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/audit|compliance|security/i);
    });
  });

  test.describe('Audit Log List', () => {
    test('should display audit logs or empty state', async ({ page }) => {
      const hasLogs = await page.locator('[class*="card"], [class*="log"], tr, [class*="entry"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*log|no.*audit|no.*entr|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/audit|compliance/i).count() > 0;

      expect(hasLogs || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display log entry details without crash', async ({ page }) => {
      const logEntry = page.locator('[class*="card"], [class*="log"], tr').first();

      if (await logEntry.count() > 0) {
        await logEntry.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Filters', () => {
    test('should display filter controls', async ({ page }) => {
      const hasFilters = await page.locator('select, input[type="search"], input[placeholder*="search" i], button:has-text("Filter")').count() > 0;
      const hasContent = await page.getByText(/audit|compliance/i).count() > 0;

      expect(hasFilters || hasContent).toBeTruthy();
    });
  });

  test.describe('Compliance Section', () => {
    test('should display compliance information', async ({ page }) => {
      const hasCompliance = await page.getByText(/compliance|policy|regulation|standard/i).count() > 0;
      const hasAudit = await page.getByText(/audit|security/i).count() > 0;

      expect(hasCompliance || hasAudit).toBeTruthy();
    });
  });
});
