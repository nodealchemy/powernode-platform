import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps API Keys Page Object Model
 *
 * Matches actual ApiKeysPage component:
 * - PageContainer with title "API Key Management"
 * - Actions: "Refresh", "Generate New Key"
 * - Keys displayed as styled divs (bg-theme-background rounded-lg p-4 border)
 * - Empty state: "No API Keys" with "Generate Your First Key"
 * - ApiKeyModal for creation
 * - Key cards show: name, status badge, masked key, Copy button, Regenerate, Revoke
 */
export class ApiKeysPage {
  readonly page: Page;
  readonly createKeyButton: Locator;
  readonly keysList: Locator;
  readonly searchInput: Locator;

  // Create Key Modal
  readonly keyNameInput: Locator;
  readonly keyDescriptionInput: Locator;
  readonly scopesChecklist: Locator;
  readonly expirationSelect: Locator;
  readonly generateButton: Locator;
  readonly copyKeyButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action: "Generate New Key"
    this.createKeyButton = page.getByRole('button', { name: /generate|create|new key/i });
    // Key cards are styled divs with border, containing key name as h3
    this.keysList = page.locator('.border:has(h3.font-medium), [class*="border"]:has(h3):has(code)');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    // ApiKeyModal form fields
    this.keyNameInput = page.locator('input[name="name"]');
    this.keyDescriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.scopesChecklist = page.locator('[class*="scope"], input[type="checkbox"]');
    this.expirationSelect = page.locator('select[name="expiration"], select[name*="expir"]');
    this.generateButton = page.getByRole('button', { name: /generate|create|save/i });
    this.copyKeyButton = page.getByRole('button', { name: /copy/i });
  }

  async goto() {
    await this.page.goto('/app/devops/api-keys');
    await this.page.waitForLoadState('networkidle');
  }

  async createKey(name: string, description?: string, scopes?: string[]) {
    await this.createKeyButton.first().click();
    await this.page.waitForTimeout(500);
    if (await this.keyNameInput.isVisible()) {
      await this.keyNameInput.fill(name);
    }
    if (description && await this.keyDescriptionInput.isVisible()) {
      await this.keyDescriptionInput.fill(description);
    }
    if (scopes) {
      for (const scope of scopes) {
        await this.page.locator(`input[value="${scope}"], label:has-text("${scope}") input`).check();
      }
    }
    await this.generateButton.first().click();
  }

  async getKeyCount(): Promise<number> {
    return await this.keysList.count();
  }

  getKeyRow(name: string): Locator {
    return this.page.locator(`div:has-text("${name}"):has(code)`).first();
  }

  async revokeKey(name: string) {
    const row = this.getKeyRow(name);
    await row.getByRole('button', { name: /revoke|delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async regenerateKey(name: string) {
    const row = this.getKeyRow(name);
    await row.getByRole('button', { name: /regenerate/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }
}
