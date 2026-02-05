import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Ralph Loops Page Object Model
 *
 * Encapsulates Ralph Loops interactions for Playwright tests.
 * Route: /app/ai/ralph-loops
 */
export class RalphLoopsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly loopCards: Locator;
  readonly createButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.loopCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="loop"]');
    this.createButton = page.getByRole('button', { name: /create|new|add/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto(ROUTES.ralphLoops);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/ralph|loop|ai/i);
  }

  async search(query: string) {
    await this.searchInput.fill(query);
  }

  async clearSearch() {
    await this.searchInput.clear();
  }

  async getLoopCount(): Promise<number> {
    return await this.loopCards.count();
  }

  async refresh() {
    await this.refreshButton.click();
  }
}
