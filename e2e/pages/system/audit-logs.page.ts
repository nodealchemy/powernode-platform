import { Page, Locator } from '@playwright/test';

/**
 * System Audit Logs Page Object Model
 *
 * The AuditLogsPage has:
 * - PageContainer with title "Audit Logs", actions: Filters, Export, Refresh
 * - AuditLogMetrics cards (Total Events, Security Events, High Risk, Failed Events)
 * - AuditLogFilters panel (toggled by Filters action button)
 * - AuditLogTable with standard <table> markup
 * - TabContainer with "Table View" and "Analytics" tabs
 */
export class AuditLogsPage {
  readonly page: Page;
  readonly logsList: Locator;
  readonly filtersButton: Locator;
  readonly searchInput: Locator;
  readonly dateRangePicker: Locator;
  readonly actionFilter: Locator;
  readonly userFilter: Locator;
  readonly exportButton: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // AuditLogTable renders standard table rows
    this.logsList = page.locator('table tbody tr');
    // The Filters toggle button in PageContainer actions
    this.filtersButton = page.getByRole('button', { name: /filter/i });
    // When filters panel is expanded, there is a "User Email" text input
    this.searchInput = page.locator('input[placeholder*="email" i], input[placeholder*="search" i]');
    // Date inputs in expanded filters
    this.dateRangePicker = page.locator('input[type="date"]');
    // Action select in expanded filters
    this.actionFilter = page.locator('select').first();
    // Source / user select in expanded filters
    this.userFilter = page.locator('select').nth(1);
    // Export button in PageContainer actions
    this.exportButton = page.getByRole('button', { name: /export/i });
    // Refresh button in PageContainer actions
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto('/app/system/audit-logs');
    await this.page.waitForLoadState('networkidle');
    // Extra wait for React state updates and API responses
    await this.page.waitForTimeout(2000);
  }

  async openFilters() {
    const filtersBtn = this.filtersButton.first();
    if (await filtersBtn.count() > 0) {
      await filtersBtn.click();
      await this.page.waitForTimeout(300);
    }
  }

  async searchLogs(query: string) {
    // First open the filters panel if not already open
    await this.openFilters();
    // The expanded filters may have a user email input
    const emailInput = this.searchInput.first();
    if (await emailInput.count() > 0) {
      await emailInput.fill(query);
      await this.page.waitForTimeout(500);
    }
  }

  async getLogCount(): Promise<number> {
    return await this.logsList.count();
  }

  async filterByAction(action: string) {
    await this.openFilters();
    if (await this.actionFilter.count() > 0) {
      await this.actionFilter.selectOption({ label: action });
      await this.page.waitForTimeout(500);
    }
  }

  async filterByUser(user: string) {
    await this.openFilters();
    const emailInput = this.searchInput.first();
    if (await emailInput.count() > 0) {
      await emailInput.fill(user);
      await this.page.waitForTimeout(500);
    }
  }
}
