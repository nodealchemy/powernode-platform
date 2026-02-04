import { Page, Locator, expect } from '@playwright/test';

/**
 * DevOps API Keys Page Object Model
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
    this.createKeyButton = page.getByRole('button', { name: /create|generate|new key/i });
    this.keysList = page.locator('table tbody tr, [class*="api-key"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    this.keyNameInput = page.locator('input[name="name"]');
    this.keyDescriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.scopesChecklist = page.locator('[class*="scope"], input[type="checkbox"]');
    this.expirationSelect = page.locator('select[name="expiration"]');
    this.generateButton = page.getByRole('button', { name: /generate|create/i });
    this.copyKeyButton = page.getByRole('button', { name: /copy/i });
  }

  async goto() {
    await this.page.goto('/app/devops/api-keys');
    await this.page.waitForLoadState('networkidle');
  }

  async createKey(name: string, description?: string, scopes?: string[]) {
    await this.createKeyButton.click();
    await this.keyNameInput.fill(name);
    if (description) {
      await this.keyDescriptionInput.fill(description);
    }
    if (scopes) {
      for (const scope of scopes) {
        await this.page.locator(`input[value="${scope}"], label:has-text("${scope}") input`).check();
      }
    }
    await this.generateButton.click();
  }

  async getKeyCount(): Promise<number> {
    return await this.keysList.count();
  }

  getKeyRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="api-key"]:has-text("${name}")`);
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
