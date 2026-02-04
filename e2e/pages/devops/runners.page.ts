import { Page, Locator, expect } from '@playwright/test';

/**
 * Runners Page Object Model
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

  // Register Runner Form
  readonly runnerNameInput: Locator;
  readonly runnerTagsInput: Locator;
  readonly registrationTokenDisplay: Locator;
  readonly copyTokenButton: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.addRunnerButton = page.getByRole('button', { name: /add.*runner|register|new/i });
    this.runnersList = page.locator('table tbody tr, [class*="runner-card"], [class*="card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });

    // Status indicators
    this.onlineRunners = page.locator('[class*="online"], :text("Online")');
    this.busyRunners = page.locator('[class*="busy"], :text("Busy")');
    this.offlineRunners = page.locator('[class*="offline"], :text("Offline")');

    // Form
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
    await this.runnerNameInput.fill(name);
    if (tags) {
      await this.runnerTagsInput.fill(tags);
    }
    await this.saveButton.first().click();
  }

  async getRunnerCount(): Promise<number> {
    return await this.runnersList.count();
  }

  getRunnerRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="card"]:has-text("${name}")`);
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
    await this.statusFilter.click();
    await this.page.getByText(status).click();
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
