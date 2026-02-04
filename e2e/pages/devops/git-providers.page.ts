import { Page, Locator, expect } from '@playwright/test';

/**
 * Git Providers Page Object Model
 */
export class GitProvidersPage {
  readonly page: Page;
  readonly addProviderButton: Locator;
  readonly providersList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;

  // Provider Form
  readonly providerTypeSelect: Locator;
  readonly providerNameInput: Locator;
  readonly providerUrlInput: Locator;
  readonly tokenInput: Locator;
  readonly saveButton: Locator;
  readonly testConnectionButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.addProviderButton = page.getByRole('button', { name: /add.*provider|connect|new/i });
    this.providersList = page.locator('table tbody tr, [class*="provider-card"], [class*="card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');

    // Form fields
    this.providerTypeSelect = page.locator('select[name*="type"], [class*="provider-type"]');
    this.providerNameInput = page.locator('input[name="name"]');
    this.providerUrlInput = page.locator('input[name="url"], input[type="url"]');
    this.tokenInput = page.locator('input[name="token"], input[type="password"]');
    this.saveButton = page.getByRole('button', { name: /save|connect|add/i });
    this.testConnectionButton = page.getByRole('button', { name: /test.*connection|verify/i });
  }

  async goto() {
    await this.page.goto('/app/devops/git');
    await this.page.waitForLoadState('networkidle');
  }

  async addProvider(type: string, name: string, url?: string) {
    await this.addProviderButton.first().click();
    await this.page.waitForTimeout(500);
    if (await this.providerTypeSelect.isVisible()) {
      await this.providerTypeSelect.selectOption(type);
    }
    await this.providerNameInput.fill(name);
    if (url && await this.providerUrlInput.isVisible()) {
      await this.providerUrlInput.fill(url);
    }
    await this.saveButton.first().click();
  }

  async getProviderCount(): Promise<number> {
    return await this.providersList.count();
  }

  getProviderRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="card"]:has-text("${name}")`);
  }

  async testConnection(name: string) {
    const row = this.getProviderRow(name);
    await row.getByRole('button', { name: /test|verify/i }).click();
  }

  async syncRepositories(name: string) {
    const row = this.getProviderRow(name);
    await row.getByRole('button', { name: /sync|refresh/i }).click();
  }

  async deleteProvider(name: string) {
    const row = this.getProviderRow(name);
    await row.getByRole('button', { name: /delete|remove/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async editProvider(name: string) {
    const row = this.getProviderRow(name);
    await row.getByRole('button', { name: /edit|settings/i }).click();
  }
}
