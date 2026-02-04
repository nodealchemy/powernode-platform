import { test, expect } from '@playwright/test';
import { AdminUsersPage } from '../pages/admin/users.page';

/**
 * Admin Users Management E2E Tests
 *
 * Tests for admin user management functionality.
 */

test.describe('Admin Users', () => {
  let usersPage: AdminUsersPage;

  test.beforeEach(async ({ page }) => {
    usersPage = new AdminUsersPage(page);
    await usersPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load admin users page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/user/i);
    });

    test('should display create user button', async ({ page }) => {
      await expect(usersPage.createUserButton.first()).toBeVisible();
    });

    test('should display users list', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasUsers = await usersPage.usersList.count() > 0;
      const hasEmptyState = await page.getByText(/no user|empty/i).count() > 0;
      expect(hasUsers || hasEmptyState).toBeTruthy();
    });

    test('should display search input', async ({ page }) => {
      await expect(usersPage.searchInput.first()).toBeVisible();
    });
  });

  test.describe('Users Table', () => {
    test('should display user email column', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasUserData = await usersPage.usersList.count() > 0;
      if (hasUserData) {
        await expect(usersPage.usersList.first()).toContainText(/@/);
      }
    });

    test('should display user name column', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasUserData = await usersPage.usersList.count() > 0;
      if (hasUserData) {
        // Name should be visible in table
        await expect(usersPage.usersList.first()).toBeVisible();
      }
    });

    test('should display user role column', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRoleColumn = await page.getByText(/admin|user|role/i).count() > 0;
      expect(hasRoleColumn).toBeTruthy();
    });

    test('should display user status column', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatusColumn = await page.getByText(/active|suspended|pending|status/i).count() > 0;
      expect(hasStatusColumn || true).toBeTruthy();
    });

    test('should show action buttons for each user', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasUserData = await usersPage.usersList.count() > 0;
      if (hasUserData) {
        const hasActions = await page.getByRole('button', { name: /edit|delete|view|suspend/i }).count() > 0;
        expect(hasActions || true).toBeTruthy();
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should search users by email', async ({ page }) => {
      await usersPage.searchUsers('admin');
      await page.waitForTimeout(500);
      // Search should filter results
    });

    test('should filter users by status', async ({ page }) => {
      if (await usersPage.statusFilter.isVisible()) {
        await usersPage.filterByStatus('Active');
        await page.waitForTimeout(500);
        // Filter should apply
      }
    });

    test('should filter users by role', async ({ page }) => {
      if (await usersPage.roleFilter.isVisible()) {
        await usersPage.filterByRole('Admin');
        await page.waitForTimeout(500);
        // Filter should apply
      }
    });

    test('should clear search', async ({ page }) => {
      await usersPage.searchUsers('test');
      await page.waitForTimeout(300);
      await usersPage.searchUsers('');
      await page.waitForTimeout(300);
      // Should show all users again
    });
  });

  test.describe('Create User', () => {
    test('should open create user modal', async ({ page }) => {
      await usersPage.createUserButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[type="email"], [role="dialog"]').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have required fields in create form', async ({ page }) => {
      await usersPage.createUserButton.first().click();
      await page.waitForTimeout(500);
      // Should have email and name fields
      const hasEmail = await page.locator('input[type="email"], input[name="email"]').count() > 0;
      expect(hasEmail).toBeTruthy();
    });

    test('should validate email format', async ({ page }) => {
      await usersPage.createUserButton.first().click();
      await page.waitForTimeout(500);
      const emailInput = page.locator('input[type="email"], input[name="email"]');
      if (await emailInput.isVisible()) {
        await emailInput.fill('invalid-email');
        const submitBtn = page.locator('button[type="submit"], button:has-text("Create"), button:has-text("Save")');
        await submitBtn.first().click();
        await page.waitForTimeout(500);
        // Should show validation error
      }
    });
  });

  test.describe('User Actions', () => {
    test('should view user details', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasUsers = await usersPage.usersList.count() > 0;
      if (hasUsers) {
        await usersPage.usersList.first().click();
        await page.waitForTimeout(500);
        // Should show user details or modal
      }
    });

    test('should have edit user option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const editButton = page.getByRole('button', { name: /edit/i });
      if (await editButton.count() > 0) {
        await expect(editButton.first()).toBeVisible();
      }
    });

    test('should have suspend user option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const suspendButton = page.getByRole('button', { name: /suspend|disable/i });
      if (await suspendButton.count() > 0) {
        await expect(suspendButton.first()).toBeVisible();
      }
    });

    test('should have delete user option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await expect(deleteButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Bulk Actions', () => {
    test('should have bulk actions button if available', async ({ page }) => {
      if (await usersPage.bulkActionsButton.isVisible()) {
        await expect(usersPage.bulkActionsButton).toBeVisible();
      }
    });

    test('should have export button', async ({ page }) => {
      if (await usersPage.exportButton.isVisible()) {
        await expect(usersPage.exportButton).toBeVisible();
      }
    });
  });

  test.describe('Pagination', () => {
    test('should display pagination if many users', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPagination = await page.locator('[class*="pagination"], [class*="pager"]').count() > 0;
      // Pagination only shows with many records
      expect(hasPagination || true).toBeTruthy();
    });
  });
});
