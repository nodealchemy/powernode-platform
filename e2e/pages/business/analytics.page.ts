import { Page, Locator, expect } from '@playwright/test';

/**
 * Business Analytics Page Object Model
 */
export class AnalyticsPage {
  readonly page: Page;
  readonly dateRangePicker: Locator;
  readonly refreshButton: Locator;
  readonly exportButton: Locator;
  readonly revenueCard: Locator;
  readonly customersCard: Locator;
  readonly mrrCard: Locator;
  readonly churnCard: Locator;
  readonly charts: Locator;

  constructor(page: Page) {
    this.page = page;
    this.dateRangePicker = page.locator('[class*="date-picker"], [class*="date-range"]');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.exportButton = page.getByRole('button', { name: /export/i });
    this.revenueCard = page.locator('[class*="card"]:has-text("Revenue")');
    this.customersCard = page.locator('[class*="card"]:has-text("Customer")');
    this.mrrCard = page.locator('[class*="card"]:has-text("MRR")');
    this.churnCard = page.locator('[class*="card"]:has-text("Churn")');
    this.charts = page.locator('canvas, [class*="chart"], svg');
  }

  async goto() {
    await this.page.goto('/app/business/analytics');
    await this.page.waitForLoadState('networkidle');
  }

  async selectDateRange(range: '7d' | '30d' | '90d' | 'custom') {
    await this.dateRangePicker.click();
    await this.page.getByText(range, { exact: false }).click();
  }

  async refresh() {
    await this.refreshButton.click();
  }

  async exportData() {
    await this.exportButton.click();
  }

  async getRevenueValue(): Promise<string> {
    return await this.revenueCard.locator('[class*="value"], [class*="amount"]').textContent() || '';
  }

  async getMrrValue(): Promise<string> {
    return await this.mrrCard.locator('[class*="value"], [class*="amount"]').textContent() || '';
  }

  async verifyChartsLoaded() {
    await expect(this.charts.first()).toBeVisible();
  }
}
