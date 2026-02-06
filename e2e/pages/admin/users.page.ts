import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Users Management Page Object Model
 *
 * Matches the actual AdminUsersPage component which uses:
 * - PageContainer with "Add New User" action (data-testid="action-add-user")
 * - UsersTable component with standard table tbody tr structure
 * - Hidden filters panel (behind "Show Filters" button)
 * - Status filter select inside filters panel
 */
export class AdminUsersPage {
  readonly page: Page;
  readonly createUserButton: Locator;
  readonly usersList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly roleFilter: Locator;
  readonly exportButton: Locator;
  readonly bulkActionsButton: Locator;
  readonly showFiltersButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action button with data-testid="action-add-user" and aria-label="Add New User"
    this.createUserButton = page.locator('[data-testid="action-add-user"], button:has-text("Add New User"), button:has-text("Add User")');
    this.usersList = page.locator('table tbody tr');
    // Search input is inside the filters panel (hidden by default)
    this.searchInput = page.locator('input[placeholder*="search" i], input[placeholder*="Search users"]');
    this.statusFilter = page.locator('select:has(option:text("All Statuses")), select:has(option:text("Active"))');
    this.roleFilter = page.locator('select:has(option:text("All Roles")), [aria-label*="role"]');
    this.exportButton = page.locator('[data-testid="action-export"], button:has-text("Export All")');
    this.bulkActionsButton = page.locator('[data-testid="action-bulk"], button:has-text("Bulk")');
    this.showFiltersButton = page.locator('[data-testid="action-filters"], button:has-text("Show Filters"), button:has-text("Hide Filters")');
  }

  async goto() {
    await this.page.goto('/app/admin/users');
    await this.page.waitForLoadState('networkidle');
  }

  async showFilters() {
    const filtersBtn = this.showFiltersButton;
    if (await filtersBtn.count() > 0 && await filtersBtn.first().isVisible()) {
      const text = await filtersBtn.first().textContent();
      if (text?.includes('Show Filters')) {
        await filtersBtn.first().click();
        await this.page.waitForTimeout(300);
      }
    }
  }

  async searchUsers(query: string) {
    await this.showFilters();
    if (await this.searchInput.count() > 0 && await this.searchInput.first().isVisible()) {
      await this.searchInput.first().fill(query);
    }
  }

  async getUserCount(): Promise<number> {
    return await this.usersList.count();
  }

  getUserRow(email: string): Locator {
    return this.page.locator(`tr:has-text("${email}")`);
  }

  async viewUser(email: string) {
    await this.getUserRow(email).click();
  }

  async suspendUser(email: string) {
    const row = this.getUserRow(email);
    await row.getByRole('button', { name: /suspend|disable/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async deleteUser(email: string) {
    const row = this.getUserRow(email);
    await row.getByRole('button', { name: /delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async impersonateUser(email: string) {
    const row = this.getUserRow(email);
    await row.getByRole('button', { name: /impersonate/i }).click();
  }

  async filterByStatus(status: string) {
    await this.showFilters();
    if (await this.statusFilter.count() > 0 && await this.statusFilter.first().isVisible()) {
      await this.statusFilter.first().selectOption({ label: status });
    }
  }

  async filterByRole(role: string) {
    await this.showFilters();
    if (await this.roleFilter.count() > 0 && await this.roleFilter.first().isVisible()) {
      await this.roleFilter.first().click();
      await this.page.getByText(role).click();
    }
  }
}
