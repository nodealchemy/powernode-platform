import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps Webhooks Page Object Model
 *
 * Matches actual WebhookManagementPage component:
 * - PageContainer with title "Webhook Management"
 * - Actions: "Refresh", "Retry Failed (N)" (conditional), "Add Webhook", "Statistics"
 * - WebhookList component for rendering
 * - WebhookModal for create/edit
 * - Stats overview with Total Endpoints, Active, Inactive, Deliveries Today, etc.
 */
export class WebhooksPage {
  readonly page: Page;
  readonly createWebhookButton: Locator;
  readonly webhooksList: Locator;
  readonly searchInput: Locator;

  // Create Webhook Modal
  readonly webhookUrlInput: Locator;
  readonly webhookNameInput: Locator;
  readonly eventsChecklist: Locator;
  readonly secretInput: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action: "Add Webhook"
    this.createWebhookButton = page.getByRole('button', { name: /add webhook|create/i });
    // WebhookList renders webhook items
    this.webhooksList = page.locator('table tbody tr, [class*="webhook"], [class*="border"]:has(button)');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    // WebhookModal form fields
    this.webhookUrlInput = page.locator('input[name="url"], input[type="url"], input[placeholder*="url" i]');
    this.webhookNameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.eventsChecklist = page.locator('[class*="event"], input[type="checkbox"]');
    this.secretInput = page.locator('input[name="secret"], input[type="password"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
  }

  async goto() {
    await this.page.goto('/app/devops/webhooks');
    await this.page.waitForLoadState('networkidle');
  }

  async createWebhook(url: string, name: string, events: string[]) {
    await this.createWebhookButton.first().click();
    await this.page.waitForTimeout(500);
    if (await this.webhookUrlInput.isVisible()) {
      await this.webhookUrlInput.fill(url);
    }
    if (await this.webhookNameInput.isVisible()) {
      await this.webhookNameInput.fill(name);
    }
    for (const event of events) {
      await this.page.locator(`input[value="${event}"], label:has-text("${event}") input`).check();
    }
    await this.saveButton.first().click();
  }

  async getWebhookCount(): Promise<number> {
    return await this.webhooksList.count();
  }

  getWebhookRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="webhook"]:has-text("${name}"), div:has-text("${name}")`);
  }

  async testWebhook(name: string) {
    const row = this.getWebhookRow(name);
    await row.getByRole('button', { name: /test/i }).click();
  }

  async disableWebhook(name: string) {
    const row = this.getWebhookRow(name);
    await row.getByRole('button', { name: /disable/i }).click();
  }

  async deleteWebhook(name: string) {
    const row = this.getWebhookRow(name);
    await row.getByRole('button', { name: /delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async viewDeliveryHistory(name: string) {
    const row = this.getWebhookRow(name);
    await row.getByRole('button', { name: /history|deliveries/i }).click();
  }
}
