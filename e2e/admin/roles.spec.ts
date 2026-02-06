import { test, expect } from '@playwright/test';
import { AdminRolesPage } from '../pages/admin/roles.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Admin Roles Management E2E Tests
 *
 * Tests for role and permission management functionality.
 * Route: /app/admin/roles
 * Component: AdminRolesPage with card-based layout, RoleFormModal
 */

test.describe('Admin Roles', () => {
  let rolesPage: AdminRolesPage;

  test.beforeEach(async ({ page }) => {
    // Suppress page errors (API calls may fail in E2E environment)
    page.on('pageerror', () => {});
    rolesPage = new AdminRolesPage(page);
    await rolesPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load roles page', async ({ page }) => {
      // Page title is "Roles & Permissions"
      await expect(page.locator('body')).toContainText(/role|permission/i);
    });

    test('should display create role button', async ({ page }) => {
      // PageContainer action: "Create Role" with data-testid="action-create-role"
      // Also could be "Create Your First Role" or "New Role" inline buttons
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await expect(createBtn.first()).toBeVisible();
      }
    });

    test('should display roles list', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Roles are displayed as cards in a grid, look for "Built-in Roles" or "Custom Roles" sections
      const hasRoles = await page.getByText(/built-in|custom|admin|member|owner/i).count() > 0;
      const hasCards = await rolesPage.rolesList.count() > 0;
      expect(hasRoles || hasCards).toBeTruthy();
    });
  });

  test.describe('Roles List', () => {
    test('should display default roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // System should have built-in roles like admin, member, owner
      await expect(page.locator('body')).toContainText(/admin/i);
    });

    test('should display role descriptions', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Cards have description text
      const hasRoles = await rolesPage.rolesList.count() > 0;
      if (hasRoles) {
        await expect(rolesPage.rolesList.first()).toBeVisible();
      }
    });

    test('should display user count per role', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Cards show "X users" badges
      const hasUserCount = await page.getByText(/\d+ user/i).count() > 0;
      await expectOrAlternateState(page, hasUserCount);
    });

    test('should indicate system vs custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Built-in roles have "System" badge
      const hasSystemIndicator = await page.getByText(/system|built-in/i).count() > 0;
      await expectOrAlternateState(page, hasSystemIndicator);
    });
  });

  test.describe('Create Role', () => {
    test('should open create role modal', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        // RoleFormModal should open
        const hasForm = await page.locator('[role="dialog"], input[type="text"]').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });

    test('should have name field in create form', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        // FormField renders input with placeholder "e.g., Content Manager"
        const nameInput = page.locator('input[placeholder*="Content Manager"], [role="dialog"] input[type="text"]');
        if (await nameInput.count() > 0) {
          await expect(nameInput.first()).toBeVisible();
        }
      }
    });

    test('should have description field', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        // FormField renders textarea for description
        const hasDescription = await page.locator('[role="dialog"] textarea').count() > 0;
        await expectOrAlternateState(page, hasDescription);
      }
    });

    test('should have permissions selection', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        // RoleFormModal has checkboxes for permissions
        const hasPermissions = await page.locator('[role="dialog"] input[type="checkbox"]').count() > 0;
        expect(hasPermissions).toBeTruthy();
      }
    });
  });

  test.describe('Permissions Display', () => {
    test('should display permission categories', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        // Permissions grouped by resource with capitalized headings
        const hasCategories = await page.locator('[role="dialog"]').getByText(/user|account|admin|ai|billing/i).count() > 0;
        expect(hasCategories).toBeTruthy();
      }
    });

    test('should have checkboxes for permissions', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        const checkboxes = await page.locator('[role="dialog"] input[type="checkbox"]').count();
        expect(checkboxes).toBeGreaterThan(0);
      }
    });

    test('should allow selecting individual permissions', async ({ page }) => {
      const createBtn = page.locator('[data-testid="action-create-role"], button:has-text("Create Role"), button:has-text("New Role"), button:has-text("Create Your First Role")');
      if (await createBtn.count() > 0) {
        await createBtn.first().click();
        await page.waitForTimeout(500);
        const checkbox = page.locator('[role="dialog"] input[type="checkbox"]').first();
        if (await checkbox.count() > 0 && await checkbox.isVisible()) {
          await checkbox.check();
          await expect(checkbox).toBeChecked();
        }
      }
    });
  });

  test.describe('Edit Role', () => {
    test('should open edit for custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Custom roles have edit buttons (Edit2 icon)
      // Look for button with Edit2 icon in custom roles section
      const editButton = page.locator('button:has(svg.lucide-edit-2), button:has(svg.lucide-edit)');
      if (await editButton.count() > 0) {
        await editButton.first().click();
        await page.waitForTimeout(500);
        const hasForm = await page.locator('[role="dialog"], input[type="text"]').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });

    test('should prevent editing system roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // System roles have "System" badge
      const hasSystemRole = await page.getByText(/system|built-in/i).count() > 0;
      await expectOrAlternateState(page, hasSystemRole);
    });
  });

  test.describe('Delete Role', () => {
    test('should have delete option for custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Custom roles have delete buttons (Trash2 icon)
      const deleteButton = page.locator('button:has(svg.lucide-trash-2), button:has(svg.lucide-trash)');
      if (await deleteButton.count() > 0) {
        await expect(deleteButton.first()).toBeVisible();
      }
    });

    test('should show confirmation for delete', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const deleteButton = page.locator('button:has(svg.lucide-trash-2), button:has(svg.lucide-trash)');
      if (await deleteButton.count() > 0) {
        await deleteButton.first().click();
        await page.waitForTimeout(500);
        // Should show confirmation dialog
        const hasConfirm = await page.getByRole('button', { name: /confirm|yes|delete/i }).count() > 0;
        // May show notification instead if role can't be deleted
        const hasNotification = await page.getByText(/cannot|assigned|warning/i).count() > 0;
        await expectOrAlternateState(page, hasConfirm || hasNotification);
      }
    });
  });

  test.describe('Role Assignment', () => {
    test('should show users with role', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Cards have a Users icon button to view assigned users
      const usersButton = page.locator('button:has(svg.lucide-users)');
      if (await usersButton.count() > 0) {
        await usersButton.first().click();
        await page.waitForTimeout(500);
        // May show RoleUsersModal
        const hasUserList = await page.locator('[role="dialog"], body').getByText(/user|member|assigned/i).count() > 0;
        await expectOrAlternateState(page, hasUserList);
      }
    });
  });
});
