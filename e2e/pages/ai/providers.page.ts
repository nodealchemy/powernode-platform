import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * AI Providers Page Object Model
 *
 * Encapsulates provider management interactions for Playwright tests.
 * Corresponds to manual testing Phase 1: Providers
 */
export class ProvidersPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly providerCards: Locator;
  readonly addProviderButton: Locator;
  readonly testConnectionButton: Locator;
  readonly syncModelsButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.providerCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="provider"]');
    this.addProviderButton = page.getByRole('button', { name: /add provider|create|configure/i });
    this.testConnectionButton = page.getByRole('button', { name: /test connection|test/i });
    this.syncModelsButton = page.getByRole('button', { name: /sync models|sync/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
  }

  /**
   * Navigate to providers page
   */
  async goto() {
    await this.page.goto(ROUTES.providers);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    // Wait for either provider cards or empty state
    await Promise.race([
      this.page.waitForSelector('[class*="card"], [class*="Card"]', { timeout: 5000 }).catch(() => {}),
      this.page.waitForSelector(':text("No providers"), :text("Configure")', { timeout: 5000 }).catch(() => {}),
    ]);
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/provider/i);
  }

  /**
   * Get provider card by name
   */
  getProviderCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Check if Ollama provider exists
   */
  async hasOllamaProvider(): Promise<boolean> {
    const ollamaCard = this.getProviderCard('Ollama');
    return await ollamaCard.count() > 0;
  }

  /**
   * Click test connection on a provider
   */
  async testConnection(providerName: string) {
    const card = this.getProviderCard(providerName);
    const testButton = card.getByRole('button', { name: /test connection|test/i });
    await testButton.click();
  }

  /**
   * Verify connection test success
   */
  async verifyConnectionSuccess() {
    // Look for success indicator - green badge, success message, or checkmark
    await expect(
      this.page.locator('[class*="success"], [class*="green"], :text("Connected"), :text("Success")')
    ).toBeVisible({ timeout: 30000 });
  }

  /**
   * Click sync models on a provider
   */
  async syncModels(providerName: string) {
    const card = this.getProviderCard(providerName);
    const syncButton = card.getByRole('button', { name: /sync models|sync/i });
    await syncButton.click();
  }

  /**
   * Open provider details/credentials
   */
  async openProviderDetails(providerName: string) {
    const card = this.getProviderCard(providerName);
    await card.click();
  }

  /**
   * Verify credentials tab is visible
   */
  async verifyCredentialsTab() {
    await expect(
      this.page.locator(':text("Credentials"), :text("API Key"), [role="tab"]:has-text("Credential")')
    ).toBeVisible();
  }

  /**
   * Verify models are listed
   */
  async verifyModelsListed() {
    // Look for common model names or model list
    await expect(
      this.page.locator(':text("llama"), :text("model"), [class*="model"]')
    ).toBeVisible({ timeout: 30000 });
  }

  /**
   * Search providers
   */
  async search(query: string) {
    await this.searchInput.fill(query);
  }

  /**
   * Clear search
   */
  async clearSearch() {
    await this.searchInput.clear();
  }

  /**
   * Get count of visible provider cards
   */
  async getProviderCount(): Promise<number> {
    return await this.providerCards.count();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No providers"), :text("Configure"), :text("Get started")')
    ).toBeVisible();
  }

  /**
   * Click add/configure provider button
   */
  async clickAddProvider() {
    await this.addProviderButton.click();
  }

  /**
   * Verify add provider modal/form is open
   */
  async verifyAddProviderModalOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"], form')
    ).toBeVisible();
  }

  /**
   * Refresh provider list
   */
  async refresh() {
    await this.refreshButton.click();
  }
}
