import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_CONVERSATION } from '../../fixtures/test-data';

/**
 * AI Conversations Page Object Model
 *
 * Encapsulates conversation interactions for Playwright tests.
 * Corresponds to manual testing Phase 3: Conversations
 */
export class ConversationsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly conversationList: Locator;
  readonly startConversationButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly agentFilter: Locator;

  // Conversation Modal/Form
  readonly titleInput: Locator;
  readonly agentSelect: Locator;
  readonly createButton: Locator;
  readonly cancelButton: Locator;

  // Chat Interface
  readonly messageInput: Locator;
  readonly sendButton: Locator;
  readonly messagesList: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.conversationList = page.locator('[class*="conversation"], [class*="chat-list"], table tbody tr');
    this.startConversationButton = page.getByRole('button', { name: /start conversation|new conversation|create/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], [aria-label*="status"]');
    this.agentFilter = page.locator('select[name*="agent"], [aria-label*="agent"]');

    // Modal inputs
    this.titleInput = page.locator('input[name="title"], input[placeholder*="title" i]');
    this.agentSelect = page.locator('select[name="agent"], [name="agent_id"]');
    this.createButton = page.getByRole('button', { name: /create|start|begin/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });

    // Chat interface
    this.messageInput = page.locator('textarea[placeholder*="message" i], input[placeholder*="type" i], textarea').last();
    this.sendButton = page.getByRole('button', { name: /send/i });
    this.messagesList = page.locator('[class*="messages"], [class*="chat-messages"]');
  }

  /**
   * Navigate to conversations page
   */
  async goto() {
    await this.page.goto(ROUTES.conversations);
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
    await expect(this.page.locator('body')).toContainText(/conversation/i);
  }

  /**
   * Click start conversation button
   */
  async clickStartConversation() {
    await this.startConversationButton.click();
  }

  /**
   * Verify start conversation modal is open
   */
  async verifyStartModalOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"]')
    ).toBeVisible();
  }

  /**
   * Fill start conversation form
   */
  async fillStartForm(title: string = TEST_CONVERSATION.title) {
    await this.titleInput.fill(title);
    // Agent select may need special handling for dropdown
  }

  /**
   * Submit start conversation form
   */
  async submitStartForm() {
    await this.createButton.click();
  }

  /**
   * Start a new conversation
   */
  async startConversation(title: string = TEST_CONVERSATION.title) {
    await this.clickStartConversation();
    await this.verifyStartModalOpen();
    await this.fillStartForm(title);
    await this.submitStartForm();
  }

  /**
   * Get conversation row by title
   */
  getConversationRow(title: string): Locator {
    return this.page.locator(`tr:has-text("${title}"), [class*="conversation"]:has-text("${title}")`);
  }

  /**
   * Open conversation detail
   */
  async openConversation(title: string) {
    const row = this.getConversationRow(title);
    await row.click();
  }

  /**
   * Click continue on a conversation
   */
  async clickContinue(title: string) {
    const row = this.getConversationRow(title);
    const continueButton = row.getByRole('button', { name: /continue/i });
    await continueButton.click();
  }

  /**
   * Send a message in conversation
   */
  async sendMessage(message: string) {
    await this.messageInput.fill(message);
    await this.sendButton.click();
  }

  /**
   * Wait for AI response
   */
  async waitForResponse() {
    // Wait for response message to appear
    await this.page.waitForSelector('[class*="message"][class*="assistant"], [class*="ai-message"]', {
      timeout: 60000,
    });
  }

  /**
   * Verify response contains expected text
   */
  async verifyResponseContains(text: string) {
    const messages = this.page.locator('[class*="message"], [class*="chat-message"]');
    await expect(messages.last()).toContainText(text, { timeout: 60000 });
  }

  /**
   * Verify context retention (AI remembers previous context)
   */
  async verifyContextRetention() {
    // Send context-setting message
    await this.sendMessage(TEST_CONVERSATION.contextTestMessage);
    await this.waitForResponse();

    // Send context-verification message
    await this.sendMessage(TEST_CONVERSATION.contextVerifyMessage);
    await this.waitForResponse();

    // Verify AI remembered the context
    await this.verifyResponseContains('Test User');
  }

  /**
   * Get message count in current conversation
   */
  async getMessageCount(): Promise<number> {
    return await this.page.locator('[class*="message"], [class*="chat-message"]').count();
  }

  /**
   * Click thumbs up on a message
   */
  async rateMessagePositive(messageIndex: number = -1) {
    const messages = this.page.locator('[class*="message"][class*="assistant"], [class*="ai-message"]');
    const targetMessage = messageIndex === -1 ? messages.last() : messages.nth(messageIndex);
    const thumbsUp = targetMessage.locator('[aria-label*="thumbs up"], button:has([class*="thumb-up"])');
    await thumbsUp.click();
  }

  /**
   * Click thumbs down on a message
   */
  async rateMessageNegative(messageIndex: number = -1) {
    const messages = this.page.locator('[class*="message"][class*="assistant"], [class*="ai-message"]');
    const targetMessage = messageIndex === -1 ? messages.last() : messages.nth(messageIndex);
    const thumbsDown = targetMessage.locator('[aria-label*="thumbs down"], button:has([class*="thumb-down"])');
    await thumbsDown.click();
  }

  /**
   * Copy message content
   */
  async copyMessage(messageIndex: number = -1) {
    const messages = this.page.locator('[class*="message"][class*="assistant"], [class*="ai-message"]');
    const targetMessage = messageIndex === -1 ? messages.last() : messages.nth(messageIndex);
    const copyButton = targetMessage.locator('[aria-label*="copy"], button:has([class*="copy"])');
    await copyButton.click();
  }

  /**
   * Regenerate AI response
   */
  async regenerateResponse(messageIndex: number = -1) {
    const messages = this.page.locator('[class*="message"][class*="assistant"], [class*="ai-message"]');
    const targetMessage = messageIndex === -1 ? messages.last() : messages.nth(messageIndex);
    const menuButton = targetMessage.locator('[aria-label*="more"], button:has([class*="dots"])');
    await menuButton.click();

    const regenerateOption = this.page.locator(':text("Regenerate")');
    await regenerateOption.click();
  }

  /**
   * Click export on a conversation
   */
  async clickExport(title: string) {
    const row = this.getConversationRow(title);
    const exportButton = row.getByRole('button', { name: /export/i });
    await exportButton.click();
  }

  /**
   * Click archive on a conversation
   */
  async clickArchive(title: string) {
    const row = this.getConversationRow(title);
    const archiveButton = row.getByRole('button', { name: /archive/i });
    await archiveButton.click();
  }

  /**
   * Click delete on a conversation
   */
  async clickDelete(title: string) {
    const row = this.getConversationRow(title);
    const deleteButton = row.getByRole('button', { name: /delete/i });
    await deleteButton.click();
  }

  /**
   * Confirm deletion
   */
  async confirmDelete() {
    const confirmButton = this.page.getByRole('button', { name: /confirm|yes|delete/i });
    await confirmButton.click();
  }

  /**
   * Search conversations
   */
  async search(query: string) {
    await this.searchInput.fill(query);
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No conversations"), :text("Start Conversation")')
    ).toBeVisible();
  }
}
