import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Users Management Page Object Model
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

  constructor(page: Page) {
    this.page = page;
    this.createUserButton = page.getByRole('button', { name: /create user|add user/i });
    this.usersList = page.locator('table tbody tr');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');
    this.roleFilter = page.locator('select[name*="role"], button:has-text("Role")');
    this.exportButton = page.getByRole('button', { name: /export/i });
    this.bulkActionsButton = page.getByRole('button', { name: /bulk|actions/i });
  }

  async goto() {
    await this.page.goto('/app/admin/users');
    await this.page.waitForLoadState('networkidle');
  }

  async searchUsers(query: string) {
    await this.searchInput.fill(query);
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
    await this.statusFilter.click();
    await this.page.getByText(status).click();
  }

  async filterByRole(role: string) {
    await this.roleFilter.click();
    await this.page.getByText(role).click();
  }
}
