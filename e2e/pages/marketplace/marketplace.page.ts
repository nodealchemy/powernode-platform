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
    this.searchInput = page.locator('input[type="search"], [data-testid="search-input"], input[placeholder*="search" i]');
    this.categoryFilter = page.locator('.search-container, [class*="type-filter"], button:has-text("Category")').first();
    this.sortSelect = page.locator('select[name*="sort"], button:has-text("Sort")');
    this.itemsList = page.locator('[class*="cursor-pointer"][class*="flex-col"]');
    this.featuredItems = page.locator('[class*="featured"], [class*="highlight"]');
    this.subscriptionsTab = page.locator('a:has-text("Subscriptions"), button:has-text("Subscriptions")').first();
    this.browseTab = page.locator('a:has-text("Browse"), button:has-text("Browse")').first();
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
    await this.searchInput.first().fill(query);
    // Marketplace search is debounced, wait for it
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
