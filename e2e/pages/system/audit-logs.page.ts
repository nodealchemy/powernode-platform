import { Page, Locator, expect } from '@playwright/test';

/**
 * System Audit Logs Page Object Model
 */
export class AuditLogsPage {
  readonly page: Page;
  readonly logsList: Locator;
  readonly searchInput: Locator;
  readonly dateRangePicker: Locator;
  readonly actionFilter: Locator;
  readonly userFilter: Locator;
  readonly exportButton: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.logsList = page.locator('table tbody tr, [class*="log-entry"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.dateRangePicker = page.locator('[class*="date-picker"], [class*="date-range"]');
    this.actionFilter = page.locator('select[name*="action"], button:has-text("Action")');
    this.userFilter = page.locator('select[name*="user"], button:has-text("User")');
    this.exportButton = page.getByRole('button', { name: /export/i });
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto('/app/system/audit-logs');
    await this.page.waitForLoadState('networkidle');
  }

  async searchLogs(query: string) {
    await this.searchInput.fill(query);
    await this.page.waitForTimeout(500);
  }

  async getLogCount(): Promise<number> {
    return await this.logsList.count();
  }

  async filterByAction(action: string) {
    await this.actionFilter.click();
    await this.page.getByText(action).click();
    await this.page.waitForTimeout(500);
  }

  async filterByUser(user: string) {
    await this.userFilter.click();
    await this.page.getByText(user).click();
    await this.page.waitForTimeout(500);
  }
}
