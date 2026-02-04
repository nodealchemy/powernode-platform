import { Page, Locator, expect } from '@playwright/test';

/**
 * Admin Settings Page Object Model
 */
export class AdminSettingsPage {
  readonly page: Page;
  readonly tabs: Locator;
  readonly saveButton: Locator;
  readonly resetButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.tabs = page.locator('[role="tab"], [class*="tab"]');
    this.saveButton = page.getByRole('button', { name: /save|update/i });
    this.resetButton = page.getByRole('button', { name: /reset|cancel/i });
  }

  async goto(section?: string) {
    const path = section ? `/app/admin/settings/${section}` : '/app/admin/settings';
    await this.page.goto(path);
    await this.page.waitForLoadState('networkidle');
  }

  async goToTab(tabName: string) {
    await this.tabs.getByText(tabName, { exact: false }).click();
  }

  async saveSettings() {
    await this.saveButton.click();
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
    const emailTab = this.page.getByText(/email/i);
    if (await emailTab.count() > 0) {
      await emailTab.first().click();
      await this.page.waitForTimeout(500);
    }
  }

  async navigateToSecuritySettings() {
    const securityTab = this.page.getByText(/security/i);
    if (await securityTab.count() > 0) {
      await securityTab.first().click();
      await this.page.waitForTimeout(500);
    }
  }
}
