import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Containers Page Object Model
 *
 * Encapsulates AI Container management interactions for Playwright tests.
 * Route: /app/ai/containers
 */
export class ContainersPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly containerCards: Locator;
  readonly createButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.containerCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="container"]');
    this.createButton = page.getByRole('button', { name: /create|new|add|deploy/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto(ROUTES.containers);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/container|deploy|ai/i);
  }

  async search(query: string) {
    await this.searchInput.fill(query);
  }

  async clearSearch() {
    await this.searchInput.clear();
  }

  async getContainerCount(): Promise<number> {
    return await this.containerCards.count();
  }

  async refresh() {
    await this.refreshButton.click();
  }
}
