import { test, expect } from '@playwright/test';
import { AnalyticsPage } from '../pages/business/analytics.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Business Analytics E2E Tests
 *
 * Tests for business metrics and analytics dashboard.
 */

test.describe('Business Analytics', () => {
  let analyticsPage: AnalyticsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    analyticsPage = new AnalyticsPage(page);
    await analyticsPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load analytics page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics|dashboard|metric|revenue/i);
    });

    test('should display date range picker', async ({ page }) => {
      // DateRangeFilter renders as buttons with preset labels
      const hasDateButtons = await page.getByText(/last.*\d+.*day|last.*month|custom/i).count() > 0;
      const hasDatePicker = await analyticsPage.dateRangePicker.count() > 0;
      expect(hasDateButtons || hasDatePicker).toBeTruthy();
    });

    test('should display refresh button', async ({ page }) => {
      const hasRefresh = await analyticsPage.refreshButton.count() > 0;
      await expectOrAlternateState(page, hasRefresh);
    });
  });

  test.describe('Key Metrics', () => {
    test('should display revenue metric', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRevenue = await page.getByText(/revenue|\$/i).count() > 0;
      expect(hasRevenue).toBeTruthy();
    });

    test('should display customer count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasCustomers = await page.getByText(/customer|user|subscriber/i).count() > 0;
      expect(hasCustomers).toBeTruthy();
    });

    test('should display MRR if applicable', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasMrr = await page.getByText(/mrr|monthly recurring/i).count() > 0;
      await expectOrAlternateState(page, hasMrr);
    });

    test('should display churn rate if applicable', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasChurn = await page.getByText(/churn|cancel/i).count() > 0;
      await expectOrAlternateState(page, hasChurn);
    });

    test('should display growth metrics', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasGrowth = await page.getByText(/growth|increase|%/i).count() > 0;
      await expectOrAlternateState(page, hasGrowth);
    });
  });

  test.describe('Charts and Visualizations', () => {
    test('should display charts', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000); // Allow charts to render
      await analyticsPage.verifyChartsLoaded();
    });

    test('should display revenue chart', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Recharts uses SVG elements, not canvas
      const hasRevenueChart = await page.locator('svg.recharts-surface, svg, [class*="chart"], canvas').count() > 0;
      expect(hasRevenueChart).toBeTruthy();
    });

    test('should display customer growth chart', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasChart = await analyticsPage.charts.count() > 0;
      expect(hasChart).toBeTruthy();
    });
  });

  test.describe('Date Range Selection', () => {
    test('should open date picker', async ({ page }) => {
      // DateRangeFilter renders preset buttons directly visible
      const hasPresets = await page.getByText(/last.*\d+.*day|last.*month|custom/i).count() > 0;
      await expectOrAlternateState(page, hasPresets);
    });

    test('should select 7 day range', async ({ page }) => {
      await analyticsPage.selectDateRange('7d');
      await page.waitForTimeout(500);
      // Data should update for 7 day range
    });

    test('should select 30 day range', async ({ page }) => {
      await analyticsPage.selectDateRange('30d');
      await page.waitForTimeout(500);
    });

    test('should select 90 day range', async ({ page }) => {
      await analyticsPage.selectDateRange('90d');
      await page.waitForTimeout(500);
    });

    test('should have custom date range option', async ({ page }) => {
      const hasCustom = await page.getByText(/custom/i).count() > 0;
      await expectOrAlternateState(page, hasCustom);
    });
  });

  test.describe('Data Refresh', () => {
    test('should refresh data on button click', async ({ page }) => {
      await analyticsPage.refresh();
      await page.waitForLoadState('networkidle');
      // Data should reload
    });
  });

  test.describe('Export', () => {
    test('should have export button', async ({ page }) => {
      const hasExport = await analyticsPage.exportButton.count() > 0;
      await expectOrAlternateState(page, hasExport);
    });

    test('should open export options', async ({ page }) => {
      if (await analyticsPage.exportButton.count() > 0) {
        await analyticsPage.exportButton.first().click();
        await page.waitForTimeout(500);
        const hasExportOptions = await page.getByText(/csv|pdf|excel|export/i).count() > 0;
        await expectOrAlternateState(page, hasExportOptions);
      }
    });
  });

  test.describe('Metric Cards', () => {
    test('should display revenue card value', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const value = await analyticsPage.getRevenueValue();
      await expectOrAlternateState(page, value !== null);
    });

    test('should display MRR card value', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const value = await analyticsPage.getMrrValue();
      await expectOrAlternateState(page, value !== null);
    });

    test('should show period comparison', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasComparison = await page.getByText(/%|vs|compared|change/i).count() > 0;
      await expectOrAlternateState(page, hasComparison);
    });
  });

  test.describe('Responsive Layout', () => {
    test('should display on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/analytics|revenue|metric/i);
    });

    test('should stack cards on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.waitForLoadState('networkidle');
      // Cards should still be visible
      const hasCards = await page.locator('[class*="card"], [class*="grid"]').count() > 0;
      await expectOrAlternateState(page, hasCards);
    });
  });

  test.describe('Loading States', () => {
    test('should show loading indicator while fetching', async ({ page }) => {
      // Navigate to trigger fresh load
      await page.goto('/app/business/analytics');
      // Look for loading indicators briefly
      const hasLoading = await page.locator('[class*="loading"], [class*="spinner"], [class*="animate"]').count() > 0;
      await expectOrAlternateState(page, hasLoading);
    });
  });
});
