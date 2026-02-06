import { Page, Locator, expect } from '@playwright/test';

/**
 * Runners Page Object Model
 *
 * Matches actual RunnersPage component:
 * - PageContainer with title "DevOps Runners"
 * - Actions: "Sync Runners" (primary), "Refresh" (secondary)
 * - No "add runner" or "register" button - runners come from git providers
 * - Runner cards rendered as RunnerCard components
 * - Search input with placeholder "Search runners..."
 * - Status filter as <select> element
 * - Stats cards showing Total, Online, Busy, Offline
 */
export class RunnersPage {
  readonly page: Page;
  readonly addRunnerButton: Locator;
  readonly runnersList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  // Runner Status Indicators
  readonly onlineRunners: Locator;
  readonly busyRunners: Locator;
  readonly offlineRunners: Locator;

  // Register Runner Form (not applicable - runners come from sync)
  readonly runnerNameInput: Locator;
  readonly runnerTagsInput: Locator;
  readonly registrationTokenDisplay: Locator;
  readonly copyTokenButton: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // The page has "Sync Runners" instead of "Add Runner"
    this.addRunnerButton = page.getByRole('button', { name: /sync.*runner|add.*runner|register|new/i });
    // Runner cards use bg-theme-surface with cursor-pointer
    this.runnersList = page.locator('.cursor-pointer:has(h3), [class*="cursor-pointer"]:has(h3)');
    this.searchInput = page.locator('input[placeholder*="search" i], input[type="search"]');
    this.statusFilter = page.locator('select');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });

    // Status indicators from StatsCards
    this.onlineRunners = page.locator('text=Online').first();
    this.busyRunners = page.locator('text=Busy').first();
    this.offlineRunners = page.locator('text=Offline').first();

    // Form fields (may not exist since runners are synced, not created)
    this.runnerNameInput = page.locator('input[name="name"]');
    this.runnerTagsInput = page.locator('input[name="tags"]');
    this.registrationTokenDisplay = page.locator('[class*="token"], code, pre');
    this.copyTokenButton = page.getByRole('button', { name: /copy/i });
    this.saveButton = page.getByRole('button', { name: /save|register|add/i });
  }

  async goto() {
    await this.page.goto('/app/devops/runners');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoRunner(id: string) {
    await this.page.goto(`/app/devops/runners/${id}`);
    await this.page.waitForLoadState('networkidle');
  }

  async registerRunner(name: string, tags?: string) {
    await this.addRunnerButton.first().click();
    await this.page.waitForTimeout(500);
    if (await this.runnerNameInput.isVisible()) {
      await this.runnerNameInput.fill(name);
      if (tags && await this.runnerTagsInput.isVisible()) {
        await this.runnerTagsInput.fill(tags);
      }
      await this.saveButton.first().click();
    }
  }

  async getRunnerCount(): Promise<number> {
    return await this.runnersList.count();
  }

  getRunnerRow(name: string): Locator {
    return this.page.locator(`[class*="cursor-pointer"]:has-text("${name}"), [class*="card"]:has-text("${name}")`);
  }

  async viewRunner(name: string) {
    await this.getRunnerRow(name).click();
    await this.page.waitForLoadState('networkidle');
  }

  async deleteRunner(name: string) {
    const row = this.getRunnerRow(name);
    await row.getByRole('button', { name: /delete|remove/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async filterByStatus(status: string) {
    await this.statusFilter.selectOption(status);
    await this.page.waitForTimeout(500);
  }

  async refresh() {
    await this.refreshButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async searchRunners(query: string) {
    await this.searchInput.fill(query);
    await this.page.waitForTimeout(500);
  }
}
