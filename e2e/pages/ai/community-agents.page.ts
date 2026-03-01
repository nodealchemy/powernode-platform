import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Community Agents Page Object Model
 *
 * Encapsulates Community Agents interactions for Playwright tests.
 * Route: /app/ai/community
 */
export class CommunityAgentsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly agentCards: Locator;
  readonly searchInput: Locator;
  readonly categoryFilter: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.agentCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="agent"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.categoryFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto(ROUTES.communityAgents);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/community|agent|ai/i);
  }

  async search(query: string) {
    await this.searchInput.fill(query);
  }

  async clearSearch() {
    await this.searchInput.clear();
  }

  async getAgentCount(): Promise<number> {
    return await this.agentCards.count();
  }

  async refresh() {
    await this.refreshButton.click();
  }
}
