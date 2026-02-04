import { Page, Locator, expect } from '@playwright/test';

/**
 * Marketplace Page Object Model
 */
export class MarketplacePage {
  readonly page: Page;
  readonly searchInput: Locator;
  readonly categoryFilter: Locator;
  readonly sortSelect: Locator;
  readonly itemsList: Locator;
  readonly featuredItems: Locator;
  readonly subscriptionsTab: Locator;
  readonly browseTab: Locator;

  constructor(page: Page) {
    this.page = page;
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.categoryFilter = page.locator('select[name*="category"], button:has-text("Category")');
    this.sortSelect = page.locator('select[name*="sort"], button:has-text("Sort")');
    this.itemsList = page.locator('[class*="item-card"], [class*="marketplace-card"], [class*="card"]');
    this.featuredItems = page.locator('[class*="featured"], [class*="highlight"]');
    this.subscriptionsTab = page.getByRole('tab', { name: /subscription|my/i });
    this.browseTab = page.getByRole('tab', { name: /browse|all/i });
  }

  async goto() {
    await this.page.goto('/app/marketplace');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoSubscriptions() {
    await this.page.goto('/app/marketplace/subscriptions');
    await this.page.waitForLoadState('networkidle');
  }

  async searchItems(query: string) {
    await this.searchInput.fill(query);
    await this.searchInput.press('Enter');
    await this.page.waitForTimeout(500);
  }

  async filterByCategory(category: string) {
    await this.categoryFilter.click();
    await this.page.getByText(category).click();
    await this.page.waitForTimeout(500);
  }

  async getItemCount(): Promise<number> {
    return await this.itemsList.count();
  }

  getItem(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}")`);
  }

  async viewItem(name: string) {
    await this.getItem(name).click();
    await this.page.waitForLoadState('networkidle');
  }
}
