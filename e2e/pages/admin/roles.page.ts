import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Roles Management Page Object Model
 *
 * Matches the actual AdminRolesPage component which uses:
 * - PageContainer with "Create Role" action (data-testid="action-create-role")
 * - Card-based layout (NOT table) - roles displayed in grid cards
 * - RoleFormModal with FormField components for name/description
 * - Checkbox-based permission selection
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
    // PageContainer action button - "Create Role"
    this.createRoleButton = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
    // Roles are displayed as cards in a grid, not table rows
    // Match the card containers that have role names
    this.rolesList = page.locator('.grid > div:has(h3)');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    // RoleFormModal uses FormField component - match by placeholder or label association
    this.roleNameInput = page.locator('input[placeholder*="Content Manager"], input[placeholder*="name" i], [role="dialog"] input[type="text"]').first();
    this.roleDescriptionInput = page.locator('textarea[placeholder*="Describe"], textarea, [role="dialog"] textarea').first();
    this.permissionsChecklist = page.locator('[role="dialog"] input[type="checkbox"], .max-h-96 input[type="checkbox"]');
    this.saveButton = page.getByRole('button', { name: /save|create|update/i });
  }

  async goto() {
    await this.page.goto('/app/admin/roles');
    await this.page.waitForLoadState('networkidle');
  }

  async createRole(name: string, description: string, permissions: string[]) {
    await this.createRoleButton.first().click();
    await this.page.waitForTimeout(500);
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
    return this.page.locator(`div:has(h3:has-text("${name}"))`);
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
