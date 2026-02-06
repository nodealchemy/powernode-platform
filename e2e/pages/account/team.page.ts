import { Page, Locator, expect } from '@playwright/test';

/**
 * Team Management Page Object Model
 *
 * Matches the actual UsersPage component at /app/users which uses:
 * - PageContainer with "Add New User" action (data-testid="action-add-user")
 * - TeamMembersTable component with standard table tbody tr structure
 * - Hidden filters panel (behind "Show Filters" button)
 */
export class TeamPage {
  readonly page: Page;
  readonly inviteButton: Locator;
  readonly membersList: Locator;
  readonly searchInput: Locator;
  readonly roleFilter: Locator;
  readonly showFiltersButton: Locator;

  // Invite/Create Modal
  readonly inviteEmailInput: Locator;
  readonly inviteRoleSelect: Locator;
  readonly sendInviteButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action button - "Add New User"
    this.inviteButton = page.locator('[data-testid="action-add-user"], button:has-text("Add New User"), button:has-text("Add User")');
    this.membersList = page.locator('table tbody tr');
    // Search input is inside the filters panel (hidden by default)
    this.searchInput = page.locator('input[placeholder*="search" i], input[placeholder*="Search users"]');
    this.roleFilter = page.locator('select:has(option:text("All Roles")), [aria-label*="role"]');
    this.showFiltersButton = page.locator('[data-testid="action-filters"], button:has-text("Show Filters"), button:has-text("Hide Filters")');

    this.inviteEmailInput = page.locator('input[type="email"]');
    this.inviteRoleSelect = page.locator('select:has(option)');
    this.sendInviteButton = page.getByRole('button', { name: /send|invite|create/i });
  }

  async goto() {
    // Actual route is /app/users (not /app/account/team)
    await this.page.goto('/app/users');
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

  async inviteMember(email: string, role?: string) {
    await this.inviteButton.first().click();
    await this.page.waitForTimeout(500);
    await this.inviteEmailInput.fill(email);
    if (role && await this.inviteRoleSelect.isVisible()) {
      await this.inviteRoleSelect.selectOption(role);
    }
    await this.sendInviteButton.click();
  }

  async searchMembers(query: string) {
    await this.showFilters();
    if (await this.searchInput.count() > 0 && await this.searchInput.first().isVisible()) {
      await this.searchInput.first().fill(query);
    }
  }

  async getMemberCount(): Promise<number> {
    return await this.membersList.count();
  }

  getMemberRow(email: string): Locator {
    return this.page.locator(`tr:has-text("${email}"), [class*="member"]:has-text("${email}")`);
  }

  async removeMember(email: string) {
    const row = this.getMemberRow(email);
    await row.getByRole('button', { name: /remove|delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async changeRole(email: string, newRole: string) {
    const row = this.getMemberRow(email);
    await row.getByRole('button', { name: /edit|change role/i }).click();
    await this.page.locator('select[name*="role"]').selectOption(newRole);
    await this.page.getByRole('button', { name: /save|update/i }).click();
  }
}
