import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

// ── Mock Data ──────────────────────────────────────────────────────────────

export const mockChatAgent = {
  id: 'agent-chat-001',
  name: 'Chat Test Agent',
  description: 'Agent for chat widget E2E tests',
  status: 'active',
  agent_type: 'assistant',
  model: 'llama3:8b',
  provider: { id: 'prov-001', name: 'Ollama' },
  execution_stats: { total_executions: 10, success_rate: 95 },
  updated_at: '2026-02-01T00:00:00Z',
};

export const mockChatAgentSecond = {
  id: 'agent-chat-002',
  name: 'Second Chat Agent',
  description: 'Second agent for multi-tab tests',
  status: 'active',
  agent_type: 'worker',
  model: 'llama3:8b',
  provider: { id: 'prov-001', name: 'Ollama' },
  execution_stats: { total_executions: 3, success_rate: 100 },
  updated_at: '2026-02-01T00:00:00Z',
};

export const mockChatConversation = {
  id: 'conv-chat-001',
  title: 'Chat Session',
  status: 'active',
  ai_agent: { id: mockChatAgent.id, name: mockChatAgent.name, agent_type: 'assistant' },
  metadata: {
    created_by: 'user-001',
    total_messages: 0,
    total_tokens: 0,
    total_cost: 0,
    last_activity: '2026-02-01T00:00:00Z',
  },
  created_at: '2026-02-01T00:00:00Z',
  updated_at: '2026-02-01T00:00:00Z',
};

export const mockChatMessages = [
  {
    id: 'msg-001',
    role: 'user',
    sender_type: 'user',
    content: 'Hello, how are you?',
    sender_info: { name: 'Test User' },
    created_at: '2026-02-01T00:01:00Z',
    metadata: {},
  },
  {
    id: 'msg-002',
    role: 'assistant',
    sender_type: 'ai',
    content: 'Hello! I am doing well. How can I help you today?',
    sender_info: { name: 'AI Assistant' },
    created_at: '2026-02-01T00:01:05Z',
    metadata: { tokens_used: 20 },
  },
];

// ── Mock Setup ─────────────────────────────────────────────────────────────

/**
 * Intercept all chat-related API routes with mock data.
 * Call BEFORE page.goto().
 */
export async function setupChatApiMocks(page: Page) {
  // Abort WebSocket connections
  await page.route('**/cable*', (route) => route.abort());

  // Mock agents list
  await page.route('**/api/v1/ai/agents*', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          items: [mockChatAgent, mockChatAgentSecond],
          pagination: { total_count: 2, page: 1, per_page: 20 },
        },
      }),
    });
  });

  // Mock active conversations (empty)
  await page.route('**/api/v1/ai/agents/*/conversations/active*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: [] }),
    });
  });

  // Mock create conversation
  await page.route('**/api/v1/ai/agents/*/conversations', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: { items: [], pagination: { total_count: 0, page: 1, per_page: 50 } },
        }),
      });
      return;
    }
    await route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({ data: { conversation: mockChatConversation } }),
    });
  });

  // Mock messages
  await page.route('**/api/v1/ai/agents/*/conversations/*/messages*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: mockChatMessages }),
    });
  });

  // Mock send_message
  await page.route('**/api/v1/ai/agents/*/conversations/*/send_message', async (route) => {
    const body = route.request().postDataJSON?.() ?? {};
    const content = body?.message?.content || 'test message';
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          user_message: {
            id: `msg-u-${Date.now()}`,
            content,
            sender_type: 'user',
            created_at: new Date().toISOString(),
          },
          assistant_message: {
            id: `msg-a-${Date.now()}`,
            content: `Mock response to: ${content}`,
            sender_type: 'ai',
            created_at: new Date().toISOString(),
            token_count: 15,
            cost_usd: '0.0001',
          },
        },
      }),
    });
  });

  // Mock rate / regenerate / misc agent sub-routes
  await page.route('**/api/v1/ai/agents/*/conversations/*/messages/*/rate', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { rating: 'thumbs_up' } }),
    });
  });

  await page.route('**/api/v1/ai/agents/*/conversations/*/messages/*/regenerate', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { regeneration_queued: true } }),
    });
  });
}

/**
 * Setup mocks that return errors for testing error handling.
 */
export async function setupChatApiErrorMocks(page: Page) {
  await page.route('**/cable*', (route) => route.abort());

  await page.route('**/api/v1/ai/agents*', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    await route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":"Internal Server Error"}' });
  });
}

/**
 * Setup send_message to return error, but agents load fine.
 */
export async function setupSendMessageErrorMock(page: Page) {
  await setupChatApiMocks(page);

  // Override the send_message route with error
  await page.route('**/api/v1/ai/agents/*/conversations/*/send_message', async (route) => {
    await route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":"Server error"}' });
  });
}

// ── Page Object ────────────────────────────────────────────────────────────

export class ChatWidgetPage {
  readonly page: Page;

  // Widget FAB
  readonly widgetButton: Locator;

  // Floating window container
  readonly floatingContainer: Locator;

  // Maximized overlay
  readonly maximizedContainer: Locator;

  // Header buttons
  readonly maximizeButton: Locator;
  readonly restoreButton: Locator;
  readonly popOutButton: Locator;
  readonly closeButton: Locator;
  readonly dockButton: Locator;

  // Online indicator
  readonly onlineIndicator: Locator;

  // Tab bar
  readonly tabBar: Locator;
  readonly newTabButton: Locator;

  // Chat interface
  readonly messageInput: Locator;
  readonly sendButton: Locator;

  // New conversation view
  readonly newConversationHeading: Locator;
  readonly agentSelectorButton: Locator;
  readonly startConversationButton: Locator;

  constructor(page: Page) {
    this.page = page;

    // Widget
    this.widgetButton = page.locator('button[aria-label="Open AI Chat"]');

    // Containers — floating has z-50 + border + rounded-xl; maximized has fixed inset-0
    this.floatingContainer = page.locator('div.fixed.z-50.border');
    this.maximizedContainer = page.locator('div.fixed.inset-0');

    // Header buttons (by title attribute)
    this.maximizeButton = page.locator('button[title="Maximize"]');
    this.restoreButton = page.locator('button[title="Restore"]');
    this.popOutButton = page.locator('button[title="Pop out"]');
    this.closeButton = page.locator('button[title="Close"]');
    this.dockButton = page.locator('button[title="Dock to main window"]');

    // Green dot in header
    this.onlineIndicator = page.locator('div.h-2.w-2.rounded-full');

    // Tab bar
    this.tabBar = page.locator('[data-tab-id]').first();
    this.newTabButton = page.locator('button[title="New conversation"]');

    // Chat
    this.messageInput = page.locator('[data-testid="message-input"]');
    this.sendButton = page.locator('[data-testid="send-button"]');

    // New conversation
    this.newConversationHeading = page.locator('h3:has-text("New Conversation")');
    this.agentSelectorButton = page.locator('button:has-text("Select an agent")');
    this.startConversationButton = page.locator('button:has-text("Start Conversation")');
  }

  // ── Navigation ───────────────────────────────────────────────────────

  async goto(route: string = ROUTES.overview) {
    await this.page.goto(route);
    await this.page.waitForLoadState('networkidle');
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  // ── Widget Actions ───────────────────────────────────────────────────

  async openChat() {
    await this.widgetButton.click();
    // Wait for floating container or new conversation heading
    await this.page.waitForTimeout(300);
  }

  async closeChat() {
    await this.closeButton.click();
    await this.page.waitForTimeout(200);
  }

  async maximize() {
    await this.maximizeButton.click();
    await this.page.waitForTimeout(200);
  }

  async restore() {
    await this.restoreButton.click();
    await this.page.waitForTimeout(200);
  }

  // ── State Queries ────────────────────────────────────────────────────

  async isWidgetVisible(): Promise<boolean> {
    return (await this.widgetButton.count()) > 0 && await this.widgetButton.isVisible();
  }

  async isChatOpen(): Promise<boolean> {
    return await this.isFloating() || await this.isMaximized();
  }

  async isMaximized(): Promise<boolean> {
    return (await this.maximizedContainer.count()) > 0 && await this.maximizedContainer.isVisible();
  }

  async isFloating(): Promise<boolean> {
    return (await this.floatingContainer.count()) > 0 && await this.floatingContainer.isVisible();
  }

  // ── Tab Management ───────────────────────────────────────────────────

  async getTabCount(): Promise<number> {
    return this.page.locator('[data-tab-id]').count();
  }

  async switchToTab(index: number) {
    const tabs = this.page.locator('[data-tab-id]');
    await tabs.nth(index).click();
    await this.page.waitForTimeout(100);
  }

  async closeTab(index: number) {
    const closeIcons = this.page.locator('[data-tab-id] span[title="Close tab"], [data-tab-id] span[role="button"]');
    if (await closeIcons.count() > index) {
      await closeIcons.nth(index).click();
      await this.page.waitForTimeout(100);
    }
  }

  async openNewTab() {
    await this.newTabButton.click();
    await this.page.waitForTimeout(200);
  }

  // ── Conversation ─────────────────────────────────────────────────────

  async selectAgent(agentName: string = mockChatAgent.name) {
    // Open the dropdown
    const dropdownTrigger = this.page.locator('button:has-text("Select an agent"), button:has-text("Loading")');
    await dropdownTrigger.click();
    await this.page.waitForTimeout(200);

    // Click the agent in the list
    await this.page.locator(`button:has-text("${agentName}")`).last().click();
    await this.page.waitForTimeout(100);
  }

  async startNewConversation(agentName: string = mockChatAgent.name) {
    await this.selectAgent(agentName);
    await this.startConversationButton.click();
    await this.page.waitForTimeout(500);
  }

  async sendMessage(text: string) {
    await this.messageInput.waitFor({ state: 'visible', timeout: 10000 });
    await this.messageInput.fill(text);
    await this.page.waitForTimeout(50);
    await this.sendButton.click();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  async getWidgetUnreadCount(): Promise<string | null> {
    const badge = this.widgetButton.locator('span.absolute');
    if (await badge.count() > 0) {
      return badge.textContent();
    }
    return null;
  }

  async getHeaderTitle(): Promise<string | null> {
    const titleEl = this.page.locator('span.text-sm.font-semibold.truncate');
    if (await titleEl.count() > 0) {
      return titleEl.textContent();
    }
    return null;
  }
}
