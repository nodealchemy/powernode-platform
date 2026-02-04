import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_AGENT } from '../../fixtures/test-data';

/**
 * AI Agents Page Object Model
 *
 * Encapsulates agent management interactions for Playwright tests.
 * Corresponds to manual testing Phase 2: Agents
 */
export class AgentsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly agentCards: Locator;
  readonly createAgentButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  // Create Agent Modal
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly systemPromptInput: Locator;
  readonly providerSelect: Locator;
  readonly modelSelect: Locator;
  readonly temperatureInput: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.agentCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="agent"]');
    this.createAgentButton = page.getByRole('button', { name: /create agent|create|new agent/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();
    this.refreshButton = page.getByRole('button', { name: /refresh/i });

    // Modal inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.systemPromptInput = page.locator('textarea[name="systemPrompt"], textarea[name="system_prompt"]');
    this.providerSelect = page.locator('select[name="provider"], [name="provider_id"]');
    this.modelSelect = page.locator('select[name="model"], [name="model_id"]');
    this.temperatureInput = page.locator('input[name="temperature"]');
    this.saveButton = page.getByRole('button', { name: /save|create|submit/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });
  }

  /**
   * Navigate to agents page
   */
  async goto() {
    await this.page.goto(ROUTES.agents);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/agent/i);
  }

  /**
   * Get agent card by name
   */
  getAgentCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Click create agent button
   */
  async clickCreateAgent() {
    await this.createAgentButton.click();
  }

  /**
   * Verify create modal is open
   */
  async verifyCreateModalOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"]')
    ).toBeVisible();
  }

  /**
   * Fill create agent form
   */
  async fillAgentForm(data: Partial<typeof TEST_AGENT> = TEST_AGENT) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
    if (data.description) {
      await this.descriptionInput.fill(data.description);
    }
    if (data.systemPrompt) {
      await this.systemPromptInput.fill(data.systemPrompt);
    }
    // Provider and model selects may need special handling
  }

  /**
   * Save agent form
   */
  async saveAgent() {
    await this.saveButton.click();
  }

  /**
   * Cancel agent form
   */
  async cancelForm() {
    await this.cancelButton.click();
  }

  /**
   * Create a new agent with given data
   */
  async createAgent(data: Partial<typeof TEST_AGENT> = TEST_AGENT) {
    await this.clickCreateAgent();
    await this.verifyCreateModalOpen();
    await this.fillAgentForm(data);
    await this.saveAgent();
  }

  /**
   * Verify agent card exists
   */
  async verifyAgentExists(name: string) {
    const card = this.getAgentCard(name);
    await expect(card).toBeVisible();
  }

  /**
   * Click execute on an agent
   */
  async clickExecute(agentName: string) {
    const card = this.getAgentCard(agentName);
    const executeButton = card.getByRole('button', { name: /execute|run/i });
    await executeButton.click();
  }

  /**
   * Enter execution prompt
   */
  async enterExecutionPrompt(prompt: string) {
    const promptInput = this.page.locator('textarea[placeholder*="prompt" i], input[placeholder*="message" i], textarea').first();
    await promptInput.fill(prompt);
  }

  /**
   * Submit execution
   */
  async submitExecution() {
    const submitButton = this.page.getByRole('button', { name: /send|submit|execute/i });
    await submitButton.click();
  }

  /**
   * Wait for execution response
   */
  async waitForExecutionResponse() {
    // Wait for streaming response or completion
    await this.page.waitForSelector('[class*="response"], [class*="message"], [class*="output"]', {
      timeout: 60000
    });
  }

  /**
   * Verify execution response contains text
   */
  async verifyResponseContains(text: string) {
    const responseArea = this.page.locator('[class*="response"], [class*="message"], [class*="output"]');
    await expect(responseArea).toContainText(text, { timeout: 60000 });
  }

  /**
   * Open agent history tab
   */
  async openHistoryTab(agentName: string) {
    const card = this.getAgentCard(agentName);
    await card.click();
    const historyTab = this.page.locator('[role="tab"]:has-text("History"), button:has-text("History")');
    await historyTab.click();
  }

  /**
   * Verify history has entries
   */
  async verifyHistoryHasEntries() {
    await expect(
      this.page.locator('[class*="history"], [class*="execution"], :text("ago")')
    ).toBeVisible();
  }

  /**
   * Click edit on an agent
   */
  async clickEdit(agentName: string) {
    const card = this.getAgentCard(agentName);
    const editButton = card.getByRole('button', { name: /edit/i });
    await editButton.click();
  }

  /**
   * Click delete on an agent
   */
  async clickDelete(agentName: string) {
    const card = this.getAgentCard(agentName);
    const deleteButton = card.getByRole('button', { name: /delete/i });
    await deleteButton.click();
  }

  /**
   * Confirm deletion in dialog
   */
  async confirmDelete() {
    const confirmButton = this.page.getByRole('button', { name: /confirm|yes|delete/i });
    await confirmButton.click();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No agents"), :text("Create Agent"), :text("Get started")')
    ).toBeVisible();
  }

  /**
   * Search agents
   */
  async search(query: string) {
    await this.searchInput.fill(query);
  }

  /**
   * Get count of visible agent cards
   */
  async getAgentCount(): Promise<number> {
    return await this.agentCards.count();
  }
}
