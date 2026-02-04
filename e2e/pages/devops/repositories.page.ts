import { Page, Locator, expect } from '@playwright/test';

/**
 * Repositories Page Object Model
 */
export class RepositoriesPage {
  readonly page: Page;
  readonly syncButton: Locator;
  readonly repositoriesList: Locator;
  readonly searchInput: Locator;
  readonly providerFilter: Locator;
  readonly branchFilter: Locator;

  constructor(page: Page) {
    this.page = page;
    this.syncButton = page.getByRole('button', { name: /sync|refresh/i });
    this.repositoriesList = page.locator('table tbody tr, [class*="repository-card"], [class*="repo-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.providerFilter = page.locator('select[name*="provider"], button:has-text("Provider")');
    this.branchFilter = page.locator('select[name*="branch"], button:has-text("Branch")');
  }

  async goto() {
    await this.page.goto('/app/devops/repositories');
    await this.page.waitForLoadState('networkidle');
  }

  async syncAll() {
    await this.syncButton.first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async searchRepositories(query: string) {
    await this.searchInput.fill(query);
    await this.page.waitForTimeout(500);
  }

  async getRepositoryCount(): Promise<number> {
    return await this.repositoriesList.count();
  }

  getRepositoryRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="card"]:has-text("${name}")`);
  }

  async viewRepository(name: string) {
    await this.getRepositoryRow(name).click();
    await this.page.waitForLoadState('networkidle');
  }

  async filterByProvider(provider: string) {
    await this.providerFilter.click();
    await this.page.getByText(provider).click();
    await this.page.waitForTimeout(500);
  }

  async configureWebhook(name: string) {
    const row = this.getRepositoryRow(name);
    await row.getByRole('button', { name: /webhook|configure/i }).click();
  }

  async viewCommits(name: string) {
    const row = this.getRepositoryRow(name);
    await row.getByRole('button', { name: /commit|history/i }).click();
  }
}
