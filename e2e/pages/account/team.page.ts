import { Page, Locator, expect } from '@playwright/test';

/**
 * Team Management Page Object Model
 */
export class TeamPage {
  readonly page: Page;
  readonly inviteButton: Locator;
  readonly membersList: Locator;
  readonly searchInput: Locator;
  readonly roleFilter: Locator;

  // Invite Modal
  readonly inviteEmailInput: Locator;
  readonly inviteRoleSelect: Locator;
  readonly sendInviteButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.inviteButton = page.getByRole('button', { name: /invite|add member/i });
    this.membersList = page.locator('table tbody tr, [class*="member-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.roleFilter = page.locator('select[name*="role"], [aria-label*="role"]');

    this.inviteEmailInput = page.locator('input[type="email"][name*="email"]');
    this.inviteRoleSelect = page.locator('select[name*="role"]');
    this.sendInviteButton = page.getByRole('button', { name: /send|invite/i });
  }

  async goto() {
    await this.page.goto('/app/account/team');
    await this.page.waitForLoadState('networkidle');
  }

  async inviteMember(email: string, role?: string) {
    await this.inviteButton.click();
    await this.inviteEmailInput.fill(email);
    if (role && await this.inviteRoleSelect.isVisible()) {
      await this.inviteRoleSelect.selectOption(role);
    }
    await this.sendInviteButton.click();
  }

  async searchMembers(query: string) {
    await this.searchInput.fill(query);
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
