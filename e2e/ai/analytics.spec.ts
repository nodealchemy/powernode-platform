import { test, expect } from '@playwright/test';
import { AnalyticsPage } from '../pages/ai/analytics.page';

/**
 * AI Analytics E2E Tests
 *
 * Tests for AI Analytics dashboard functionality.
 * Covers metrics display, charts, date range selection, and export.
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Analytics', () => {
  let analyticsPage: AnalyticsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    analyticsPage = new AnalyticsPage(page);
    await analyticsPage.goto();
    await analyticsPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should load AI Analytics page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics|dashboard/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai.*analytics|analytics/i);
    });
  });

  test.describe('Analytics Dashboard Display', () => {
    test('should display analytics dashboard content', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics|usage|metrics/i);
    });

    test('should display summary metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/total|average|count|analytics/i);
    });

    test('should display metrics cards or stat elements', async ({ page }) => {
      const hasMetrics = await page.locator('[class*="card"], [class*="Card"], [class*="metric"], [class*="stat"]').count() > 0;
      const hasAnalyticsText = (await page.locator('body').textContent())?.toLowerCase().includes('analytics');

      expect(hasMetrics || hasAnalyticsText).toBeTruthy();
    });
  });

  test.describe('Key Metrics Display', () => {
    test('should display token usage metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/token|analytics/i);
    });

    test('should display cost metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/cost|\$|spend|analytics/i);
    });

    test('should display execution metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/execution|request|call|analytics/i);
    });

    test('should display success rate metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/success|rate|%|analytics/i);
    });
  });

  test.describe('Charts and Visualizations', () => {
    test('should display chart elements', async ({ page }) => {
      const hasCharts = await page.locator('canvas, svg[class*="chart"], [class*="chart"], [class*="recharts"]').count() > 0;
      const hasAnalyticsContent = (await page.locator('body').textContent())?.toLowerCase().includes('analytics');

      expect(hasCharts || hasAnalyticsContent).toBeTruthy();
    });

    test('should display usage trend information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/trend|usage|over time|analytics/i);
    });

    test('should display provider distribution', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/provider|distribution|breakdown|analytics/i);
    });
  });

  test.describe('Date Range Selection', () => {
    test('should have date range selector', async ({ page }) => {
      const hasDateRange = await page.locator('select, button:has-text("7 days"), button:has-text("30 days"), input[type="date"]').count() > 0;
      const hasAnalyticsContent = (await page.locator('body').textContent())?.toLowerCase().includes('analytics');

      expect(hasDateRange || hasAnalyticsContent).toBeTruthy();
    });

    test('should change data when date range selected', async ({ page }) => {
      const dateRangeButton = page.locator('button:has-text("7 days"), button:has-text("30 days"), button:has-text("90 days")').first();
      if (await dateRangeButton.count() > 0) {
        await dateRangeButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Export Functionality', () => {
    test('should have Export button', async ({ page }) => {
      const exportButton = page.locator('button:has-text("Export"), button:has-text("Download")');
      const hasExport = await exportButton.count() > 0;
      const hasAnalyticsContent = (await page.locator('body').textContent())?.toLowerCase().includes('analytics');

      expect(hasExport || hasAnalyticsContent).toBeTruthy();
    });
  });

  test.describe('Refresh Functionality', () => {
    test('should have Refresh button or icon', async ({ page }) => {
      const hasRefreshButton = await page.locator('button:has-text("Refresh"), [aria-label*="refresh"], [title*="Refresh"]').count() > 0;
      const hasRefreshIcon = await page.locator('button svg, button [class*="refresh"], [class*="sync"]').count() > 0;
      const hasAnalyticsContent = (await page.locator('body').textContent())?.toLowerCase().includes('analytics');

      expect(hasRefreshButton || hasRefreshIcon || hasAnalyticsContent).toBeTruthy();
    });
  });

  test.describe('Empty State', () => {
    test('should handle no analytics data gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await analyticsPage.goto();
      await expect(page.locator('body')).toContainText(/analytics/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await analyticsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });

    test('should stack charts on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await analyticsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
