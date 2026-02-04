import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps Webhooks Page Object Model
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
    this.createWebhookButton = page.getByRole('button', { name: /create|add webhook/i });
    this.webhooksList = page.locator('table tbody tr, [class*="webhook-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    this.webhookUrlInput = page.locator('input[name="url"], input[type="url"]');
    this.webhookNameInput = page.locator('input[name="name"]');
    this.eventsChecklist = page.locator('[class*="event"], input[type="checkbox"]');
    this.secretInput = page.locator('input[name="secret"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
  }

  async goto() {
    await this.page.goto('/app/devops/webhooks');
    await this.page.waitForLoadState('networkidle');
  }

  async createWebhook(url: string, name: string, events: string[]) {
    await this.createWebhookButton.click();
    await this.webhookUrlInput.fill(url);
    await this.webhookNameInput.fill(name);
    for (const event of events) {
      await this.page.locator(`input[value="${event}"], label:has-text("${event}") input`).check();
    }
    await this.saveButton.click();
  }

  async getWebhookCount(): Promise<number> {
    return await this.webhooksList.count();
  }

  getWebhookRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="webhook"]:has-text("${name}")`);
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
