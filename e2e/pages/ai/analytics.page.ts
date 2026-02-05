import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * AI Analytics Page Object Model
 *
 * Encapsulates analytics dashboard interactions for Playwright tests.
 * Supports metrics display, chart visualization, date range selection, and export.
 */
export class AnalyticsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly metricsCards: Locator;
  readonly charts: Locator;
  readonly refreshButton: Locator;
  readonly exportButton: Locator;
  readonly dateRangeSelector: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.metricsCards = page.locator('[class*="card"], [class*="Card"], [class*="metric"], [class*="stat"]');
    this.charts = page.locator('canvas, svg[class*="chart"], [class*="chart"], [class*="recharts"]');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.exportButton = page.getByRole('button', { name: /export|download/i });
    this.dateRangeSelector = page.locator('select, button:has-text("7 days"), button:has-text("30 days"), input[type="date"]');
  }

  /**
   * Navigate to analytics page
   */
  async goto() {
    await this.page.goto(ROUTES.analytics);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    await this.page.waitForTimeout(1000);
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/analytics/i);
  }

  /**
   * Verify metrics cards are displayed
   */
  async verifyMetricsDisplayed() {
    const hasMetrics = await this.metricsCards.count() > 0;
    expect(hasMetrics).toBeTruthy();
  }

  /**
   * Verify charts are rendered
   */
  async verifyChartsDisplayed() {
    const hasCharts = await this.charts.count() > 0;
    expect(hasCharts).toBeTruthy();
  }

  /**
   * Select date range
   */
  async selectDateRange(range: string) {
    const rangeButton = this.page.locator(`button:has-text("${range}"), option:has-text("${range}")`);
    if (await rangeButton.count() > 0) {
      await rangeButton.first().click();
    }
  }

  /**
   * Click export button
   */
  async clickExport() {
    if (await this.exportButton.count() > 0) {
      await this.exportButton.click();
    }
  }

  /**
   * Refresh analytics data
   */
  async refresh() {
    if (await this.refreshButton.count() > 0) {
      await this.refreshButton.click();
    }
  }

  /**
   * Get count of metrics cards
   */
  async getMetricsCount(): Promise<number> {
    return await this.metricsCards.count();
  }

  /**
   * Get count of charts
   */
  async getChartsCount(): Promise<number> {
    return await this.charts.count();
  }

  /**
   * Verify token usage metric exists
   */
  async verifyTokenMetric() {
    await expect(this.page.locator('body')).toContainText(/token/i);
  }

  /**
   * Verify cost metric exists
   */
  async verifyCostMetric() {
    await expect(this.page.locator('body')).toContainText(/cost|\$/i);
  }

  /**
   * Verify execution metric exists
   */
  async verifyExecutionMetric() {
    await expect(this.page.locator('body')).toContainText(/execution|request|call/i);
  }

  /**
   * Verify success rate metric exists
   */
  async verifySuccessRateMetric() {
    await expect(this.page.locator('body')).toContainText(/success|rate|%/i);
  }
}
