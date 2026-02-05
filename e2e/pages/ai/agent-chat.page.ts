import { Page, Locator, expect } from '@playwright/test';

/**
 * Agent Chat Page Object Model
 *
 * POM for Agent Chat Page E2E tests.
 * Route: /app/ai/agents/:agentId/chat
 */
export class AgentChatPage {
  readonly page: Page;

  // Sidebar
  readonly newConversationButton: Locator;
  readonly conversationItems: Locator;
  readonly emptyConversationMessage: Locator;

  // Chat panel
  readonly messageInput: Locator;
  readonly sendButton: Locator;

  // Create conversation modal
  readonly createConversationModal: Locator;

  constructor(page: Page) {
    this.page = page;

    // Sidebar
    this.newConversationButton = page.getByRole('button', { name: /new conversation/i });
    this.conversationItems = page.locator('button[class*="text-left"]');
    this.emptyConversationMessage = page.locator('text=No conversations yet');

    // Chat panel
    this.messageInput = page.locator('[data-testid="message-input"]');
    this.sendButton = page.locator('[data-testid="send-button"]');

    // Modal
    this.createConversationModal = page.locator('[role="dialog"]');
  }

  async goto(agentId: string) {
    await this.page.goto(`/app/ai/agents/${agentId}/chat`);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async selectConversation(title: string) {
    const item = this.conversationItems.filter({ hasText: title });
    await item.click();
  }

  async openCreateConversationModal() {
    await this.newConversationButton.click();
    await expect(this.createConversationModal).toBeVisible();
  }

  async sendMessage(msg: string) {
    await this.messageInput.fill(msg);
    await this.sendButton.click();
  }

  async verifyUserMessageSent(msg: string) {
    await expect(this.page.locator('body')).toContainText(msg);
  }

  async getConversationCount(): Promise<number> {
    return await this.conversationItems.count();
  }

  async verifyBreadcrumbs() {
    await expect(this.page.locator('body')).toContainText('Agents');
    await expect(this.page.locator('body')).toContainText('Chat');
  }
}
