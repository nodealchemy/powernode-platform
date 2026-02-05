import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_AGENT_CARD } from '../../fixtures/test-data';

/**
 * Agent Cards Page Object Model
 *
 * Encapsulates A2A Agent Card management interactions for Playwright tests.
 * Supports card listing, creation, editing, deletion, and detail views.
 */
export class AgentCardsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly cardList: Locator;
  readonly createCardButton: Locator;
  readonly refreshButton: Locator;
  readonly searchInput: Locator;

  // Create/Edit Form
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly urlInput: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  // Detail View
  readonly backToListButton: Locator;
  readonly editButton: Locator;
  readonly deleteButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.cardList = page.locator('[data-testid="agent-card-list"], [data-testid="agent-card-row"], table tbody tr, [class*="agent-card-item"], [class*="card"]');
    this.createCardButton = page.getByRole('button', { name: /create agent card|create|new/i });
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    // Form inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.urlInput = page.locator('input[name="url"], input[placeholder*="url" i], input[type="url"]');
    this.saveButton = page.getByRole('button', { name: /save|create|submit/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });

    // Detail actions
    this.backToListButton = page.getByRole('button', { name: /back|list/i });
    this.editButton = page.getByRole('button', { name: /edit/i });
    this.deleteButton = page.getByRole('button', { name: /delete/i });
  }

  /**
   * Navigate to agent cards page
   */
  async goto() {
    await this.page.goto(ROUTES.agentCards);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    await this.page.waitForTimeout(1000);
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/agent card|a2a/i);
  }

  /**
   * Click create agent card button
   */
  async clickCreateCard() {
    await this.createCardButton.click();
  }

  /**
   * Verify create form is open
   */
  async verifyFormOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"], form, [class*="editor"]')
    ).toBeVisible();
  }

  /**
   * Fill agent card form
   */
  async fillCardForm(data: Partial<typeof TEST_AGENT_CARD> = TEST_AGENT_CARD) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
    if (data.description) {
      await this.descriptionInput.fill(data.description);
    }
    if (data.url && await this.urlInput.count() > 0) {
      await this.urlInput.fill(data.url);
    }
  }

  /**
   * Save agent card form
   */
  async saveCard() {
    await this.saveButton.click();
  }

  /**
   * Cancel form
   */
  async cancelForm() {
    await this.cancelButton.click();
  }

  /**
   * Create a new agent card
   */
  async createCard(data: Partial<typeof TEST_AGENT_CARD> = TEST_AGENT_CARD) {
    await this.clickCreateCard();
    await this.page.waitForTimeout(500);
    await this.fillCardForm(data);
    await this.saveCard();
  }

  /**
   * Get card row by name
   */
  getCardRow(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), tr:has-text("${name}"), [class*="item"]:has-text("${name}")`);
  }

  /**
   * Click on a card to view details
   */
  async openCardDetail(name: string) {
    const row = this.getCardRow(name);
    await row.click();
  }

  /**
   * Click edit on a card
   */
  async clickEdit(name: string) {
    const row = this.getCardRow(name);
    const editBtn = row.getByRole('button', { name: /edit/i });
    if (await editBtn.count() > 0) {
      await editBtn.click();
    } else {
      await this.editButton.click();
    }
  }

  /**
   * Click delete on a card
   */
  async clickDelete(name: string) {
    const row = this.getCardRow(name);
    const deleteBtn = row.getByRole('button', { name: /delete/i });
    if (await deleteBtn.count() > 0) {
      await deleteBtn.click();
    } else {
      await this.deleteButton.click();
    }
  }

  /**
   * Confirm deletion in dialog
   */
  async confirmDelete() {
    const confirmButton = this.page.getByRole('button', { name: /confirm|yes|delete/i });
    await confirmButton.click();
  }

  /**
   * Back to list from detail view
   */
  async backToList() {
    if (await this.backToListButton.count() > 0) {
      await this.backToListButton.click();
    }
  }

  /**
   * Get count of visible cards
   */
  async getCardCount(): Promise<number> {
    return await this.cardList.count();
  }

  /**
   * Verify empty state
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No agent cards"), :text("Create Agent Card"), :text("no cards")')
    ).toBeVisible();
  }

  /**
   * Search cards
   */
  async search(query: string) {
    if (await this.searchInput.count() > 0) {
      await this.searchInput.first().fill(query);
    }
  }

  /**
   * Clear search
   */
  async clearSearch() {
    if (await this.searchInput.count() > 0) {
      await this.searchInput.first().clear();
    }
  }

  /**
   * Refresh card list
   */
  async refresh() {
    if (await this.refreshButton.count() > 0) {
      await this.refreshButton.click();
    }
  }
}
