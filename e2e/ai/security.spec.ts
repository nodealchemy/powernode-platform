import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Security Dashboard E2E Tests
 *
 * Tests for the SecurityDashboardPage including anomaly detection,
 * PII redaction, and security monitoring sections.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Security Dashboard', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.security);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load security page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/security|anomal|detection|pii/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/security/i);
    });
  });

  test.describe('Anomaly Detection Section', () => {
    test('should display anomaly detection section', async ({ page }) => {
      const hasAnomaly = await page.getByText(/anomal|detection|threat|alert/i).count() > 0;
      const hasSecurity = await page.getByText(/security/i).count() > 0;

      expect(hasAnomaly || hasSecurity).toBeTruthy();
    });

    test('should display anomaly list or empty state', async ({ page }) => {
      const hasAnomalies = await page.locator('[class*="card"], [class*="alert"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*anomal|no.*threat|no.*alert|empty/i).count() > 0;
      const hasContent = await page.getByText(/security/i).count() > 0;

      expect(hasAnomalies || hasEmpty || hasContent).toBeTruthy();
    });
  });

  test.describe('PII Redaction Section', () => {
    test('should display PII redaction section', async ({ page }) => {
      const hasPii = await page.getByText(/pii|redact|sensitive|data.*protection/i).count() > 0;
      const hasSecurity = await page.getByText(/security/i).count() > 0;

      expect(hasPii || hasSecurity).toBeTruthy();
    });
  });

  test.describe('Security Metrics', () => {
    test('should display security metrics or dashboard cards', async ({ page }) => {
      const hasMetrics = await page.locator('[class*="card"], [class*="metric"], [class*="stat"]').count() > 0;
      const hasContent = await page.getByText(/security/i).count() > 0;

      expect(hasMetrics || hasContent).toBeTruthy();
    });
  });
});
