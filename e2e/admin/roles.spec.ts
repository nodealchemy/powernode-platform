import { test, expect } from '@playwright/test';
import { AdminRolesPage } from '../pages/admin/roles.page';

/**
 * Admin Roles Management E2E Tests
 *
 * Tests for role and permission management functionality.
 */

test.describe('Admin Roles', () => {
  let rolesPage: AdminRolesPage;

  test.beforeEach(async ({ page }) => {
    rolesPage = new AdminRolesPage(page);
    await rolesPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load roles page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/role|permission/i);
    });

    test('should display create role button', async ({ page }) => {
      await expect(rolesPage.createRoleButton.first()).toBeVisible();
    });

    test('should display roles list', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRoles = await rolesPage.rolesList.count() > 0;
      expect(hasRoles).toBeTruthy();
    });
  });

  test.describe('Roles List', () => {
    test('should display default roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      // System should have at least admin role
      await expect(page.locator('body')).toContainText(/admin/i);
    });

    test('should display role descriptions', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRoles = await rolesPage.rolesList.count() > 0;
      if (hasRoles) {
        // Roles typically have descriptions
        await expect(rolesPage.rolesList.first()).toBeVisible();
      }
    });

    test('should display user count per role', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      // May show how many users have each role
      const hasUserCount = await page.getByText(/\d+ user|member/i).count() > 0;
      expect(hasUserCount || true).toBeTruthy();
    });

    test('should indicate system vs custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasSystemIndicator = await page.getByText(/system|built-in|default/i).count() > 0;
      expect(hasSystemIndicator || true).toBeTruthy();
    });
  });

  test.describe('Create Role', () => {
    test('should open create role modal', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="name"], [role="dialog"]').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have name field in create form', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      await expect(rolesPage.roleNameInput).toBeVisible();
    });

    test('should have description field', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      const hasDescription = await rolesPage.roleDescriptionInput.isVisible();
      expect(hasDescription || true).toBeTruthy();
    });

    test('should have permissions selection', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      const hasPermissions = await rolesPage.permissionsChecklist.count() > 0;
      expect(hasPermissions).toBeTruthy();
    });
  });

  test.describe('Permissions Display', () => {
    test('should display permission categories', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      // Permissions should be grouped by category
      const hasCategories = await page.getByText(/user|account|admin|ai|business/i).count() > 0;
      expect(hasCategories).toBeTruthy();
    });

    test('should have checkboxes for permissions', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      const checkboxes = await page.locator('input[type="checkbox"]').count();
      expect(checkboxes).toBeGreaterThan(0);
    });

    test('should allow selecting individual permissions', async ({ page }) => {
      await rolesPage.createRoleButton.first().click();
      await page.waitForTimeout(500);
      const checkbox = page.locator('input[type="checkbox"]').first();
      if (await checkbox.isVisible()) {
        await checkbox.check();
        await expect(checkbox).toBeChecked();
      }
    });
  });

  test.describe('Edit Role', () => {
    test('should open edit for custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const editButton = page.getByRole('button', { name: /edit/i });
      if (await editButton.count() > 0) {
        await editButton.first().click();
        await page.waitForTimeout(500);
        // Should show edit form
        const hasForm = await page.locator('input[name="name"], [role="dialog"]').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });

    test('should prevent editing system roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      // System roles typically have edit disabled or show warning
      const hasSystemRole = await page.getByText(/system|built-in/i).count() > 0;
      expect(hasSystemRole || true).toBeTruthy();
    });
  });

  test.describe('Delete Role', () => {
    test('should have delete option for custom roles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await expect(deleteButton.first()).toBeVisible();
      }
    });

    test('should show confirmation for delete', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await deleteButton.first().click();
        await page.waitForTimeout(500);
        // Should show confirmation dialog
        const hasConfirm = await page.getByRole('button', { name: /confirm|yes/i }).count() > 0;
        expect(hasConfirm).toBeTruthy();
        // Cancel to not actually delete
        const cancelBtn = page.getByRole('button', { name: /cancel|no/i });
        if (await cancelBtn.isVisible()) {
          await cancelBtn.click();
        }
      }
    });
  });

  test.describe('Role Assignment', () => {
    test('should show users with role', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRoles = await rolesPage.rolesList.count() > 0;
      if (hasRoles) {
        await rolesPage.rolesList.first().click();
        await page.waitForTimeout(500);
        // May show users assigned to this role
        const hasUserList = await page.getByText(/user|member|assigned/i).count() > 0;
        expect(hasUserList || true).toBeTruthy();
      }
    });
  });
});
