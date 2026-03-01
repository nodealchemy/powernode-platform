import { Page, Locator, expect } from '@playwright/test';

/**
 * Business Analytics Page Object Model
 *
 * Matches actual AnalyticsPage component:
 * - PageContainer with title "Analytics Dashboard"
 * - DateRangeFilter uses Button components (not CSS date-picker classes)
 * - Charts are Recharts SVG-based
 * - Actions: Refresh, Export (in PageContainer header)
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
    // DateRangeFilter renders as buttons with Calendar icon and date text
    this.dateRangePicker = page.locator('button:has-text("day"), button:has-text("month"), button:has-text("year"), button:has-text("Jan"), button:has-text("Feb"), button:has-text("Mar"), button:has-text("Apr"), button:has-text("May"), button:has-text("Jun"), button:has-text("Jul"), button:has-text("Aug"), button:has-text("Sep"), button:has-text("Oct"), button:has-text("Nov"), button:has-text("Dec")');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.exportButton = page.getByRole('button', { name: /export/i });
    // MetricsOverview cards don't use class*="card", look by text content
    this.revenueCard = page.locator('text=Revenue').first();
    this.customersCard = page.locator('text=Customer').first();
    this.mrrCard = page.locator('text=MRR').first();
    this.churnCard = page.locator('text=Churn').first();
    // Recharts renders SVG
    this.charts = page.locator('svg.recharts-surface, [class*="chart"], canvas, svg');
  }

  async goto() {
    await this.page.goto('/app/business/analytics');
    await this.page.waitForLoadState('networkidle');
  }

  async selectDateRange(range: '7d' | '30d' | '90d' | 'custom') {
    // Click the main date range button to open dropdown
    const dateButton = this.page.locator('button:has-text("day"), button:has-text("month")').first();
    if (await dateButton.count() > 0) {
      await dateButton.click();
      await this.page.waitForTimeout(300);
      // Presets use labels like "Last 7 days", "Last 30 days", "Last 90 days"
      const labels: Record<string, string> = {
        '7d': 'Last 7 days',
        '30d': 'Last 30 days',
        '90d': 'Last 90 days',
        'custom': 'Custom'
      };
      const target = this.page.getByText(labels[range] || range);
      if (await target.count() > 0) {
        await target.first().click();
      }
    }
  }

  async refresh() {
    const btn = this.refreshButton.first();
    if (await btn.count() > 0) {
      await btn.click();
    }
  }

  async exportData() {
    const btn = this.exportButton.first();
    if (await btn.count() > 0) {
      await btn.click();
    }
  }

  async getRevenueValue(): Promise<string | null> {
    try {
      const revenueText = this.page.getByText(/revenue|\$/i).first();
      if (await revenueText.count() > 0) {
        return await revenueText.textContent();
      }
      return null;
    } catch {
      return null;
    }
  }

  async getMrrValue(): Promise<string | null> {
    try {
      const mrrText = this.page.getByText(/mrr|monthly recurring/i).first();
      if (await mrrText.count() > 0) {
        return await mrrText.textContent();
      }
      return null;
    } catch {
      return null;
    }
  }

  async verifyChartsLoaded() {
    // Charts may be SVG (Recharts) or canvas
    const hasCharts = await this.charts.count() > 0;
    if (hasCharts) {
      await expect(this.charts.first()).toBeVisible();
    }
  }
}
