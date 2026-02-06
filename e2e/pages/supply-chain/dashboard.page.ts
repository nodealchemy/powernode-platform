import { Page } from '@playwright/test';

/**
 * Supply Chain Dashboard Page Object Model
 *
 * Handles navigation and selectors for all supply chain pages:
 * - Dashboard overview
 * - SBOMs
 * - Container Images
 * - Attestations
 * - Vendors
 * - License Policies (mapped to /licenses route)
 */
export class SupplyChainDashboardPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async goto() {
    await this.page.goto('/app/supply-chain');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoSboms() {
    await this.page.goto('/app/supply-chain/sboms');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoContainers() {
    await this.page.goto('/app/supply-chain/containers');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoAttestations() {
    await this.page.goto('/app/supply-chain/attestations');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoVendors() {
    await this.page.goto('/app/supply-chain/vendors');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoLicenses() {
    await this.page.goto('/app/supply-chain/licenses');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for the page to finish loading (spinner gone or content visible).
   * Handles dashboard error state, loading state, or successful render.
   */
  async waitForReady() {
    // Wait for either the page content or an error state to appear
    await this.page.waitForLoadState('networkidle');
    // Give time for React to render after API response
    await this.page.waitForTimeout(500);
  }

  /**
   * Check if the page rendered successfully (not stuck on a loading spinner).
   * Returns true if meaningful content is visible.
   */
  async hasPageContent(): Promise<boolean> {
    const body = this.page.locator('body');
    const text = await body.innerText();
    // Page has content if it's not just a loading spinner
    return text.length > 50;
  }
}
