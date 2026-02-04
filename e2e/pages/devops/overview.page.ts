import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps Overview Page Object Model
 */
export class DevOpsOverviewPage {
  readonly page: Page;
  readonly refreshButton: Locator;

  // Stat Cards
  readonly gitProvidersCard: Locator;
  readonly repositoriesCard: Locator;
  readonly runnersCard: Locator;
  readonly webhooksCard: Locator;
  readonly integrationsCard: Locator;
  readonly apiKeysCard: Locator;

  // Status Sections
  readonly runnerHealthSection: Locator;
  readonly webhookDeliveriesSection: Locator;
  readonly commitActivitySection: Locator;

  // Quick Access Links
  readonly quickAccessLinks: Locator;

  // Alerts
  readonly alertsSection: Locator;

  constructor(page: Page) {
    this.page = page;
    this.refreshButton = page.getByRole('button', { name: /refresh/i });

    // Stat cards - match by text content
    this.gitProvidersCard = page.locator('[class*="card"]:has-text("Git Provider"), [class*="stat"]:has-text("Provider")');
    this.repositoriesCard = page.locator('[class*="card"]:has-text("Repositor"), [class*="stat"]:has-text("Repositor")');
    this.runnersCard = page.locator('[class*="card"]:has-text("Runner"), [class*="stat"]:has-text("Runner")');
    this.webhooksCard = page.locator('[class*="card"]:has-text("Webhook"), [class*="stat"]:has-text("Webhook")');
    this.integrationsCard = page.locator('[class*="card"]:has-text("Integration"), [class*="stat"]:has-text("Integration")');
    this.apiKeysCard = page.locator('[class*="card"]:has-text("API Key"), [class*="stat"]:has-text("API Key")');

    // Status sections
    this.runnerHealthSection = page.locator('[class*="card"]:has-text("Runner Health"), section:has-text("Runner Health")');
    this.webhookDeliveriesSection = page.locator('[class*="card"]:has-text("Webhook Deliver"), section:has-text("Webhook Deliver")');
    this.commitActivitySection = page.locator('[class*="card"]:has-text("Commit"), section:has-text("Commit")');

    // Quick access
    this.quickAccessLinks = page.locator('[class*="quick-access"], [class*="card"] a, [class*="link-card"]');

    // Alerts
    this.alertsSection = page.locator('[class*="alert"], [class*="attention"], [class*="warning"]');
  }

  async goto() {
    await this.page.goto('/app/devops');
    await this.page.waitForLoadState('networkidle');
  }

  async refresh() {
    await this.refreshButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToGitProviders() {
    await this.page.getByText(/git provider/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToRepositories() {
    await this.page.getByText(/repositor/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToPipelines() {
    await this.page.getByText(/pipeline/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToRunners() {
    await this.page.getByText(/runner/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToWebhooks() {
    await this.page.getByText(/webhook/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToIntegrations() {
    await this.page.getByText(/integration/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToApiKeys() {
    await this.page.getByText(/api key/i).first().click();
    await this.page.waitForLoadState('networkidle');
  }
}
