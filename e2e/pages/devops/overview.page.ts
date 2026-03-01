import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps Overview Page Object Model
 *
 * Matches actual DevOpsOverviewPage component:
 * - PageContainer with title "DevOps Overview"
 * - Actions: "Refresh" (or "Refreshing...")
 * - StatCard components for Git Providers, Repositories, Runners, Webhooks, Integrations, API Keys
 * - Status sections: Runner Health, Webhook Deliveries, Commit Activity
 * - QuickLinkCard components for navigation
 * - Conditional alerts section
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

    // StatCard titles are rendered as <p className="text-sm text-theme-secondary">{title}</p>
    this.gitProvidersCard = page.locator('text=Git Providers').first();
    this.repositoriesCard = page.locator('text=Repositories').first();
    this.runnersCard = page.locator('text=Runners Online').first();
    this.webhooksCard = page.locator('text=Webhooks Active').first();
    this.integrationsCard = page.locator('text=Integrations').first();
    this.apiKeysCard = page.locator('text=API Keys').first();

    // Status sections have h3 headings
    this.runnerHealthSection = page.locator('text=Runner Health').first();
    this.webhookDeliveriesSection = page.locator('text=Webhook Deliveries Today').first();
    this.commitActivitySection = page.locator('text=Commit Activity').first();

    // Quick access section
    this.quickAccessLinks = page.locator('text=Quick Access').first();

    // Alerts
    this.alertsSection = page.locator('text=Attention Required').first();
  }

  async goto() {
    await this.page.goto('/app/devops');
    await this.page.waitForLoadState('networkidle');
  }

  async refresh() {
    const btn = this.refreshButton.first();
    if (await btn.count() > 0) {
      await btn.click();
      await this.page.waitForLoadState('networkidle');
    }
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
