import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_CONTEXT } from '../../fixtures/test-data';

/**
 * AI Contexts Page Object Model
 *
 * Encapsulates context management interactions for Playwright tests.
 * Supports context browsing, searching, creation, and detail views.
 */
export class ContextsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly contextList: Locator;
  readonly newContextButton: Locator;
  readonly refreshButton: Locator;
  readonly searchInput: Locator;

  // Tab Navigation
  readonly browseTab: Locator;
  readonly searchTab: Locator;
  readonly createTab: Locator;

  // Create Context Form
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly scopeSelector: Locator;
  readonly submitButton: Locator;
  readonly cancelButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.contextList = page.locator('[class*="card"], [class*="Card"], [class*="list"], [class*="grid"]');
    this.newContextButton = page.getByRole('button', { name: /new context|create|create new/i });
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]');

    // Tab navigation
    this.browseTab = page.getByRole('button', { name: /browse/i });
    this.searchTab = page.getByRole('button', { name: /search/i });
    this.createTab = page.getByRole('button', { name: /create new|create/i });

    // Form inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.scopeSelector = page.locator('select[name="scope"], [name="scope"], [role="combobox"]');
    this.submitButton = page.getByRole('button', { name: /create context|save|submit/i });
    this.cancelButton = page.getByRole('button', { name: /cancel|back/i });
  }

  /**
   * Navigate to contexts page
   */
  async goto() {
    await this.page.goto(ROUTES.contexts);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    await this.page.waitForTimeout(1000);
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/context/i);
  }

  /**
   * Switch to Browse tab
   */
  async switchToBrowseTab() {
    if (await this.browseTab.count() > 0) {
      await this.browseTab.click();
      await this.page.waitForTimeout(300);
    }
  }

  /**
   * Switch to Search tab
   */
  async switchToSearchTab() {
    if (await this.searchTab.count() > 0) {
      await this.searchTab.click();
      await this.page.waitForTimeout(300);
    }
  }

  /**
   * Switch to Create tab
   */
  async switchToCreateTab() {
    if (await this.createTab.count() > 0) {
      await this.createTab.click();
      await this.page.waitForTimeout(300);
    }
  }

  /**
   * Fill create context form
   */
  async fillContextForm(data: Partial<typeof TEST_CONTEXT> = TEST_CONTEXT) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
  }

  /**
   * Submit context form
   */
  async submitForm() {
    await this.submitButton.click();
  }

  /**
   * Cancel context form
   */
  async cancelForm() {
    await this.cancelButton.click();
  }

  /**
   * Search contexts
   */
  async search(query: string) {
    await this.searchInput.first().fill(query);
  }

  /**
   * Clear search input
   */
  async clearSearch() {
    await this.searchInput.first().clear();
  }

  /**
   * Get context card by name
   */
  getContextCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Click on a context to view details
   */
  async openContextDetail(name: string) {
    const card = this.getContextCard(name);
    await card.click();
  }

  /**
   * Get count of visible context items
   */
  async getContextCount(): Promise<number> {
    return await this.contextList.count();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No contexts"), :text("Create your first"), :text("no contexts")')
    ).toBeVisible();
  }

  /**
   * Refresh context list
   */
  async refresh() {
    if (await this.refreshButton.count() > 0) {
      await this.refreshButton.click();
    }
  }

  /**
   * Navigate to a specific context detail page
   */
  async gotoDetail(contextId: string) {
    await this.page.goto(`${ROUTES.contexts}/${contextId}`);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Click Add Entry button on detail page
   */
  async clickAddEntry() {
    const addButton = this.page.getByRole('button', { name: /add entry|add/i });
    await addButton.click();
  }

  /**
   * Switch to Settings tab on detail page
   */
  async switchToSettingsTab() {
    const settingsTab = this.page.getByRole('button', { name: /settings/i });
    if (await settingsTab.count() > 0) {
      await settingsTab.click();
      await this.page.waitForTimeout(300);
    }
  }

  /**
   * Switch to Entries tab on detail page
   */
  async switchToEntriesTab() {
    const entriesTab = this.page.getByRole('button', { name: /entries/i });
    if (await entriesTab.count() > 0) {
      await entriesTab.click();
      await this.page.waitForTimeout(300);
    }
  }
}
