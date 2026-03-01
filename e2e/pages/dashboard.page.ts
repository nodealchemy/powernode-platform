import { Page, Locator, expect } from '@playwright/test';

/**
 * Dashboard Page Object Model
 */
export class DashboardPage {
  readonly page: Page;
  readonly sidebar: Locator;
  readonly mainContent: Locator;
  readonly userMenu: Locator;
  readonly notificationBell: Locator;
  readonly accountSwitcher: Locator;
  readonly searchInput: Locator;

  constructor(page: Page) {
    this.page = page;
    this.sidebar = page.locator('nav, [class*="sidebar"], aside');
    this.mainContent = page.locator('main, [role="main"], [class*="content"]');
    this.userMenu = page.locator('[class*="user-menu"], [class*="avatar"], :text("System Admin"), :text("Admin")').first();
    this.notificationBell = page.locator('[class*="notification"], [class*="bell"], button:has(svg)');
    this.accountSwitcher = page.locator('[class*="account-switcher"], [class*="org-switcher"], :text("Powernode Admin")');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
  }

  async goto() {
    await this.page.goto('/app/dashboard');
    await this.page.waitForLoadState('networkidle');
  }

  async verifyLoaded() {
    // Verify dashboard loaded by checking for sidebar navigation
    await expect(this.sidebar.first()).toBeVisible();
  }

  async navigateTo(menuItem: string) {
    await this.sidebar.getByText(menuItem, { exact: false }).click();
    await this.page.waitForLoadState('networkidle');
  }

  async openUserMenu() {
    await this.userMenu.click();
  }

  async logout() {
    await this.openUserMenu();
    await this.page.getByText(/logout|sign out/i).click();
  }

  async switchAccount(accountName: string) {
    if (await this.accountSwitcher.isVisible()) {
      await this.accountSwitcher.click();
      await this.page.getByText(accountName).click();
    }
  }

  async search(query: string) {
    await this.searchInput.fill(query);
    await this.searchInput.press('Enter');
  }
}
