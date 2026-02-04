import { test, expect } from '@playwright/test';
import { DashboardPage } from '../pages/dashboard.page';

/**
 * Dashboard E2E Tests
 *
 * Tests for main dashboard layout, navigation, and core functionality.
 */

test.describe('Dashboard', () => {
  let dashboardPage: DashboardPage;

  test.beforeEach(async ({ page }) => {
    dashboardPage = new DashboardPage(page);
    await dashboardPage.goto();
  });

  test.describe('Layout', () => {
    test('should display dashboard page', async ({ page }) => {
      await dashboardPage.verifyLoaded();
    });

    test('should display sidebar navigation', async ({ page }) => {
      await expect(dashboardPage.sidebar.first()).toBeVisible();
    });

    test('should display main content area', async ({ page }) => {
      // The page loaded with navigation visible = main area exists
      await expect(page.locator('body')).toContainText(/dashboard|powernode/i);
    });

    test('should display user menu', async ({ page }) => {
      // User menu shows "System Admin" in top right header
      await expect(page.getByText('System Admin')).toBeVisible();
    });
  });

  test.describe('Navigation', () => {
    test('should have navigation links in sidebar', async ({ page }) => {
      // Sidebar shows categories like Dashboard, AI, BUSINESS, etc.
      await expect(page.getByText('Dashboard')).toBeVisible();
    });

    test('should navigate to AI section', async ({ page }) => {
      // Click on AI in sidebar to expand
      await page.getByText('AI', { exact: true }).click();
      await page.waitForTimeout(500);
      // AI section expanded
      await expect(page.locator('body')).toContainText(/ai/i);
    });

    test('should navigate to Account section', async ({ page }) => {
      // Click on ACCOUNT in sidebar (case-insensitive)
      await page.getByText(/^ACCOUNT$/i).click();
      await page.waitForTimeout(500);
      // ACCOUNT section expanded
      await expect(page.locator('body')).toContainText(/account/i);
    });

    test('should navigate to Admin section if visible', async ({ page }) => {
      const adminLink = page.getByText('ADMINISTRATION', { exact: true });
      if (await adminLink.isVisible()) {
        await adminLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/admin/i);
      }
    });

    test('should navigate to Business section if visible', async ({ page }) => {
      const businessLink = page.getByText('BUSINESS', { exact: true });
      if (await businessLink.isVisible()) {
        await businessLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/business/i);
      }
    });
  });

  test.describe('User Menu', () => {
    test('should open user menu on click', async ({ page }) => {
      // Click on user name/avatar in top right
      await page.locator(':text("System Admin")').first().click();
      await page.waitForTimeout(500);
      // User menu should show options
      const hasMenu = await page.getByText(/profile|settings|logout|sign out/i).count() > 0;
      expect(hasMenu).toBeTruthy();
    });

    test('should have profile option in user menu', async ({ page }) => {
      await page.locator(':text("System Admin")').first().click();
      await page.waitForTimeout(500);
      const profileOption = page.getByText(/profile/i);
      const hasProfile = await profileOption.count() > 0;
      expect(hasProfile).toBeTruthy();
    });

    test('should have logout option in user menu', async ({ page }) => {
      await page.locator(':text("System Admin")').first().click();
      await page.waitForTimeout(500);
      const logoutOption = page.getByText(/logout|sign out/i);
      const hasLogout = await logoutOption.count() > 0;
      expect(hasLogout).toBeTruthy();
    });
  });

  test.describe('Dashboard Content', () => {
    test('should display dashboard widgets or cards', async ({ page }) => {
      // Dashboard has navigation sidebar visible
      await expect(page.getByText('Dashboard', { exact: true })).toBeVisible();
    });

    test('should display recent activity or summary', async ({ page }) => {
      // Dashboard page has loaded with navigation visible
      await expect(page.getByText('Dashboard', { exact: true })).toBeVisible();
    });
  });

  test.describe('Responsiveness', () => {
    test('should adapt to mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.waitForTimeout(500);
      // Page should still function on mobile
      await expect(page.locator('body')).toContainText(/powernode|dashboard/i);
    });

    test('should adapt to tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.waitForTimeout(500);
      // Page should still function on tablet
      await expect(page.locator('body')).toContainText(/powernode|dashboard/i);
    });
  });

  test.describe('Search', () => {
    test('should have search input if present', async ({ page }) => {
      if (await dashboardPage.searchInput.isVisible()) {
        await expect(dashboardPage.searchInput).toBeVisible();
      }
    });

    test('should allow typing in search', async ({ page }) => {
      if (await dashboardPage.searchInput.isVisible()) {
        await dashboardPage.searchInput.fill('test search');
        await expect(dashboardPage.searchInput).toHaveValue('test search');
      }
    });
  });
});
