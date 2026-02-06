import { Page, Locator, expect } from '@playwright/test';

/**
 * Git Providers Page Object Model
 *
 * Matches actual GitProvidersPage component:
 * - PageContainer with title "Git Providers"
 * - Actions: Refresh, "Add Provider"
 * - Provider cards as expandable divs with provider info
 * - GitProviderModal for create/edit
 * - "Add More Providers" section with GitHub/GitLab/Gitea/Bitbucket buttons
 * - NO search input on this page
 * - NO status filter on this page
 * - CredentialModal for managing credentials
 */
export class GitProvidersPage {
  readonly page: Page;
  readonly addProviderButton: Locator;
  readonly providersList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;

  // Provider Form (in GitProviderModal)
  readonly providerTypeSelect: Locator;
  readonly providerNameInput: Locator;
  readonly providerUrlInput: Locator;
  readonly tokenInput: Locator;
  readonly saveButton: Locator;
  readonly testConnectionButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action: "Add Provider"
    this.addProviderButton = page.getByRole('button', { name: /add.*provider|connect|new/i });
    // Provider cards use bg-theme-surface border rounded-lg
    this.providersList = page.locator('[class*="bg-theme-surface"][class*="border"][class*="rounded-lg"]:has(h3)');
    // No search input on this page
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    // No status filter on this page
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');

    // Form fields (in GitProviderModal)
    this.providerTypeSelect = page.locator('select[name*="type"], [class*="provider-type"]');
    this.providerNameInput = page.locator('input[name="name"]');
    this.providerUrlInput = page.locator('input[name="url"], input[type="url"]');
    this.tokenInput = page.locator('input[name="token"], input[type="password"]');
    this.saveButton = page.getByRole('button', { name: /save|connect|add|create/i });
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
    if (await this.providerNameInput.isVisible()) {
      await this.providerNameInput.fill(name);
    }
    if (url && await this.providerUrlInput.isVisible()) {
      await this.providerUrlInput.fill(url);
    }
    await this.saveButton.first().click();
  }

  async getProviderCount(): Promise<number> {
    return await this.providersList.count();
  }

  getProviderRow(name: string): Locator {
    return this.page.locator(`[class*="bg-theme-surface"]:has-text("${name}"), [class*="card"]:has-text("${name}")`);
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
