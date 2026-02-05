import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Chat Channels Page Object Model
 *
 * Encapsulates Chat Channels interactions for Playwright tests.
 * Route: /app/ai/chat-channels
 */
export class ChatChannelsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly channelList: Locator;
  readonly createButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.channelList = page.locator('[class*="card"], [class*="Card"], [class*="channel"], [data-testid*="channel"]');
    this.createButton = page.getByRole('button', { name: /create|new|add/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  async goto() {
    await this.page.goto(ROUTES.chatChannels);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/channel|chat|ai/i);
  }

  async search(query: string) {
    await this.searchInput.fill(query);
  }

  async clearSearch() {
    await this.searchInput.clear();
  }

  async getChannelCount(): Promise<number> {
    return await this.channelList.count();
  }

  async refresh() {
    await this.refreshButton.click();
  }
}
