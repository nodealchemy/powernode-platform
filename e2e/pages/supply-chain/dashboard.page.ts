import { Page, Locator, expect } from '@playwright/test';

/**
 * Supply Chain Dashboard Page Object Model
 */
export class SupplyChainDashboardPage {
  readonly page: Page;
  readonly sbomCard: Locator;
  readonly containersCard: Locator;
  readonly attestationsCard: Locator;
  readonly vendorsCard: Locator;
  readonly licensesCard: Locator;
  readonly searchInput: Locator;
  readonly refreshButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.sbomCard = page.locator('[class*="card"]:has-text("SBOM"), [class*="card"]:has-text("Software Bill")');
    this.containersCard = page.locator('[class*="card"]:has-text("Container")');
    this.attestationsCard = page.locator('[class*="card"]:has-text("Attestation")');
    this.vendorsCard = page.locator('[class*="card"]:has-text("Vendor")');
    this.licensesCard = page.locator('[class*="card"]:has-text("License")');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
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
}
