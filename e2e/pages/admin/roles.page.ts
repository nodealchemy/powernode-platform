import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Roles Management Page Object Model
 */
export class AdminRolesPage {
  readonly page: Page;
  readonly createRoleButton: Locator;
  readonly rolesList: Locator;
  readonly searchInput: Locator;

  // Create/Edit Role Modal
  readonly roleNameInput: Locator;
  readonly roleDescriptionInput: Locator;
  readonly permissionsChecklist: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.createRoleButton = page.getByRole('button', { name: /create role|add role/i });
    this.rolesList = page.locator('table tbody tr, [class*="role-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    this.roleNameInput = page.locator('input[name="name"]');
    this.roleDescriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.permissionsChecklist = page.locator('[class*="permission"], input[type="checkbox"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
  }

  async goto() {
    await this.page.goto('/app/admin/roles');
    await this.page.waitForLoadState('networkidle');
  }

  async createRole(name: string, description: string, permissions: string[]) {
    await this.createRoleButton.click();
    await this.roleNameInput.fill(name);
    await this.roleDescriptionInput.fill(description);

    for (const permission of permissions) {
      await this.page.locator(`input[value="${permission}"], label:has-text("${permission}") input`).check();
    }

    await this.saveButton.click();
  }

  async getRoleCount(): Promise<number> {
    return await this.rolesList.count();
  }

  getRoleRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="role"]:has-text("${name}")`);
  }

  async editRole(name: string) {
    const row = this.getRoleRow(name);
    await row.getByRole('button', { name: /edit/i }).click();
  }

  async deleteRole(name: string) {
    const row = this.getRoleRow(name);
    await row.getByRole('button', { name: /delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async duplicateRole(name: string) {
    const row = this.getRoleRow(name);
    await row.getByRole('button', { name: /duplicate|copy/i }).click();
  }
}
