import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Settings Page Object Model
 *
 * Matches the actual AdminSettingsPage component which uses:
 * - PageContainer with title "Admin Settings"
 * - AdminSettingsTabs component with tab navigation (button-based tabs)
 * - Sub-routes for each tab: overview, payment-gateways, email, proxy, security, rate-limiting, performance
 * - No global save button on overview tab (each sub-tab has its own form/actions)
 */
export class AdminSettingsPage {
  readonly page: Page;
  readonly tabs: Locator;
  readonly saveButton: Locator;
  readonly resetButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // AdminSettingsTabs renders button elements for each tab
    this.tabs = page.locator('nav[aria-label="Admin Settings"] button, [role="tab"], [class*="tab"]');
    // Save button may not exist on overview, but present on some sub-tabs
    this.saveButton = page.locator('[data-testid*="save"], button:has-text("Save"), button:has-text("Update"), button[type="submit"]');
    this.resetButton = page.getByRole('button', { name: /reset|cancel/i });
  }

  async goto(section?: string) {
    const path = section ? `/app/admin/settings/${section}` : '/app/admin/settings';
    await this.page.goto(path);
    await this.page.waitForLoadState('networkidle');
  }

  async goToTab(tabName: string) {
    // Click the tab button in the AdminSettingsTabs nav
    const tabButton = this.page.locator(`nav[aria-label="Admin Settings"] button:has-text("${tabName}"), button:has-text("${tabName}")`);
    if (await tabButton.count() > 0) {
      await tabButton.first().click();
      await this.page.waitForTimeout(500);
    }
  }

  async saveSettings() {
    if (await this.saveButton.count() > 0 && await this.saveButton.first().isVisible()) {
      await this.saveButton.first().click();
    }
  }

  // Platform Settings
  async setPlatformName(name: string) {
    await this.page.locator('input[name="platformName"], input[name="site_name"]').fill(name);
  }

  async setPlatformLogo(filePath: string) {
    await this.page.locator('input[type="file"]').setInputFiles(filePath);
  }

  // Email Settings
  async configureSmtp(config: { host: string; port: string; user: string; password: string }) {
    await this.page.locator('input[name="smtp_host"], input[name="host"]').fill(config.host);
    await this.page.locator('input[name="smtp_port"], input[name="port"]').fill(config.port);
    await this.page.locator('input[name="smtp_user"], input[name="username"]').fill(config.user);
    await this.page.locator('input[name="smtp_password"], input[name="password"]').fill(config.password);
  }

  async testEmailConnection() {
    await this.page.getByRole('button', { name: /test|verify/i }).click();
  }

  // Security Settings
  async enableTwoFactor(enabled: boolean) {
    const checkbox = this.page.locator('input[name*="two_factor"], input[name*="2fa"]');
    if (enabled) {
      await checkbox.check();
    } else {
      await checkbox.uncheck();
    }
  }

  async setSessionTimeout(minutes: number) {
    await this.page.locator('input[name*="session_timeout"], input[name*="timeout"]').fill(String(minutes));
  }

  async setPasswordPolicy(minLength: number, requireSpecial: boolean) {
    await this.page.locator('input[name*="min_length"]').fill(String(minLength));
    const specialCheckbox = this.page.locator('input[name*="special"]');
    if (requireSpecial) {
      await specialCheckbox.check();
    } else {
      await specialCheckbox.uncheck();
    }
  }

  async navigateToEmailSettings() {
    // Click the "Email Settings" tab in AdminSettingsTabs
    const emailTab = this.page.locator('nav[aria-label="Admin Settings"] button:has-text("Email"), button:has-text("Email Settings")');
    if (await emailTab.count() > 0) {
      await emailTab.first().click();
      await this.page.waitForTimeout(500);
    } else {
      // Fallback: navigate directly
      await this.page.goto('/app/admin/settings/email');
      await this.page.waitForLoadState('networkidle');
    }
  }

  async navigateToSecuritySettings() {
    // Click the "Security" tab in AdminSettingsTabs
    const securityTab = this.page.locator('nav[aria-label="Admin Settings"] button:has-text("Security")');
    if (await securityTab.count() > 0) {
      await securityTab.first().click();
      await this.page.waitForTimeout(500);
    } else {
      // Fallback: navigate directly
      await this.page.goto('/app/admin/settings/security');
      await this.page.waitForLoadState('networkidle');
    }
  }
}
