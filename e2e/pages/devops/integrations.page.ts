import { Page, Locator, expect } from '@playwright/test';

/**
 * Integrations Page Object Model
 *
 * Matches actual IntegrationsPage component:
 * - PageContainer with title "My Integrations"
 * - Actions: Refresh, "Browse Marketplace", "Add Integration"
 * - Uses IntegrationCard components in a grid
 * - Filter dropdowns: status <select> and type <select>
 * - NO search input on this page
 * - Empty state: "No integrations yet"
 */
export class IntegrationsPage {
  readonly page: Page;
  readonly addIntegrationButton: Locator;
  readonly integrationsList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly categoryFilter: Locator;

  // Integration Templates (on /new page)
  readonly templatesList: Locator;

  // Integration Wizard Steps
  readonly templateSelectStep: Locator;
  readonly credentialsStep: Locator;
  readonly configurationStep: Locator;
  readonly reviewStep: Locator;

  // Form Fields
  readonly integrationNameInput: Locator;
  readonly credentialsInputs: Locator;
  readonly configInputs: Locator;
  readonly testConnectionButton: Locator;
  readonly saveButton: Locator;
  readonly nextButton: Locator;
  readonly backButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.addIntegrationButton = page.getByRole('button', { name: /add.*integration|new.*integration|connect|browse/i });
    // IntegrationCard components in a grid
    this.integrationsList = page.locator('[class*="grid"] > div:has(h3), [class*="grid"] > div:has(h4)');
    // No search input on this page, but use safe selector
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    // Status filter is a <select> element
    this.statusFilter = page.locator('select').first();
    // Type filter is the second <select>
    this.categoryFilter = page.locator('select').nth(1);

    // Templates (on /new page)
    this.templatesList = page.locator('[class*="template-card"], [class*="template-item"], [class*="card"]');

    // Wizard steps
    this.templateSelectStep = page.locator('[class*="step"]:has-text("Template"), [class*="step"]:has-text("Select")');
    this.credentialsStep = page.locator('[class*="step"]:has-text("Credential")');
    this.configurationStep = page.locator('[class*="step"]:has-text("Config")');
    this.reviewStep = page.locator('[class*="step"]:has-text("Review")');

    // Form
    this.integrationNameInput = page.locator('input[name="name"]');
    this.credentialsInputs = page.locator('input[type="password"], input[name*="key"], input[name*="secret"]');
    this.configInputs = page.locator('input[name*="config"], select[name*="config"]');
    this.testConnectionButton = page.getByRole('button', { name: /test.*connection|verify/i });
    this.saveButton = page.getByRole('button', { name: /save|create|finish/i });
    this.nextButton = page.getByRole('button', { name: /next|continue/i });
    this.backButton = page.getByRole('button', { name: /back|previous/i });
  }

  async goto() {
    await this.page.goto('/app/devops/integrations');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoNew() {
    await this.page.goto('/app/devops/integrations/new');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoIntegration(id: string) {
    await this.page.goto(`/app/devops/integrations/${id}`);
    await this.page.waitForLoadState('networkidle');
  }

  async getIntegrationCount(): Promise<number> {
    return await this.integrationsList.count();
  }

  getIntegrationRow(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), div:has-text("${name}")`);
  }

  async viewIntegration(name: string) {
    await this.getIntegrationRow(name).first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async deleteIntegration(name: string) {
    const row = this.getIntegrationRow(name);
    await row.getByRole('button', { name: /delete|remove/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async testConnection(name: string) {
    const row = this.getIntegrationRow(name);
    await row.getByRole('button', { name: /test|verify/i }).click();
  }

  async filterByStatus(status: string) {
    await this.statusFilter.selectOption(status);
    await this.page.waitForTimeout(500);
  }

  async filterByCategory(category: string) {
    await this.categoryFilter.selectOption(category);
    await this.page.waitForTimeout(500);
  }

  async searchIntegrations(query: string) {
    // No search input on main integrations page - safe no-op
    const searchVisible = await this.searchInput.count() > 0;
    if (searchVisible) {
      await this.searchInput.fill(query);
      await this.page.waitForTimeout(500);
    }
  }

  async selectTemplate(templateName: string) {
    await this.page.locator(`[class*="template"]:has-text("${templateName}"), [class*="card"]:has-text("${templateName}")`).click();
    await this.page.waitForTimeout(500);
  }

  async nextStep() {
    await this.nextButton.first().click();
    await this.page.waitForTimeout(500);
  }

  async previousStep() {
    await this.backButton.first().click();
    await this.page.waitForTimeout(500);
  }
}
