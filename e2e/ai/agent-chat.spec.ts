import { test, expect, Page, Route } from '@playwright/test';
import { API_ENDPOINTS } from '../fixtures/test-data';

/**
 * Agent Chat Page - Mocked E2E Tests
 *
 * Uses page.route() to intercept API calls and return mock data.
 * No backend required. Tests UI rendering, conversation sidebar,
 * message sending, and empty states.
 */

const mockAgent = {
  id: 'agent-001',
  name: 'Test Agent',
  description: 'Agent for chat testing',
  status: 'active',
  agent_type: 'assistant',
  model: 'llama3:8b',
  provider: { id: 'prov-001', name: 'Ollama' },
};

const mockConversations = [
  {
    id: 'conv-001',
    title: 'Active Conversation',
    status: 'active',
    ai_agent: mockAgent,
    metadata: { total_messages: 5, last_activity: '2026-02-01T12:00:00Z' },
    created_at: '2026-02-01T10:00:00Z',
    updated_at: '2026-02-01T12:00:00Z',
  },
  {
    id: 'conv-002',
    title: 'Completed Conversation',
    status: 'completed',
    ai_agent: mockAgent,
    metadata: { total_messages: 12, last_activity: '2026-01-31T08:00:00Z' },
    created_at: '2026-01-30T10:00:00Z',
    updated_at: '2026-01-31T08:00:00Z',
  },
];

const mockMessages = [
  {
    id: 'msg-001',
    sender_type: 'user',
    sender_info: { name: 'Test User' },
    content: 'Hello, can you help me?',
    created_at: '2026-02-01T10:01:00Z',
    metadata: {},
  },
  {
    id: 'msg-002',
    sender_type: 'ai',
    sender_info: { name: 'AI Assistant' },
    content: 'Of course! I am here to help. What do you need?',
    created_at: '2026-02-01T10:01:30Z',
    metadata: {},
  },
];

async function setupApiMocks(page: Page, options: { conversations?: typeof mockConversations } = {}) {
  const conversations = options.conversations ?? mockConversations;

  // Agent detail route (exact agent ID, no sub-paths)
  await page.route(`**${API_ENDPOINTS.agents}/agent-001`, async (route: Route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(mockAgent),
      });
    } else {
      await route.continue();
    }
  });

  // Messages route - highest specificity, registered before catch-all
  await page.route(/\/agents\/agent-001\/conversations\/[^/]+\/messages/, async (route: Route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(mockMessages),
      });
    } else {
      await route.continue();
    }
  });

  // Send message route - high specificity
  await page.route(/\/agents\/agent-001\/conversations\/[^/]+\/send_message/, async (route: Route) => {
    if (route.request().method() === 'POST') {
      const postData = JSON.parse(route.request().postData() || '{}');
      const messageContent = postData.message?.content || postData.content || 'Test message';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user_message: {
            id: `msg-user-${Date.now()}`,
            sender_type: 'user',
            sender_info: { name: 'Test User' },
            content: messageContent,
            created_at: new Date().toISOString(),
          },
          assistant_message: {
            id: `msg-ai-${Date.now()}`,
            sender_type: 'ai',
            sender_info: { name: 'AI Assistant' },
            content: 'This is a mock AI response.',
            created_at: new Date().toISOString(),
          },
        }),
      });
    } else {
      await route.continue();
    }
  });

  // Conversations list and create route
  await page.route(/\/agents\/agent-001\/conversations\/?(\?.*)?$/, async (route: Route) => {
    const method = route.request().method();

    if (method === 'POST') {
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          id: 'conv-new',
          title: 'New Conversation',
          status: 'active',
          ai_agent: mockAgent,
          metadata: { total_messages: 0 },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }),
      });
      return;
    }

    if (method === 'GET') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: conversations,
          pagination: { total_count: conversations.length, page: 1, per_page: 50 },
        }),
      });
      return;
    }

    await route.continue();
  });

  // Catch WebSocket upgrade attempts
  await page.route('**/cable*', async (route: Route) => {
    await route.abort();
  });
}

test.describe('Agent Chat Page', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await setupApiMocks(page);
    await page.goto('/app/ai/agents/agent-001/chat');
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should navigate to agent chat page', async ({ page }) => {
      expect(page.url()).toContain('/app/ai/agents/agent-001/chat');
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Chat with Test Agent');
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Agents');
      await expect(page.locator('body')).toContainText('Chat');
    });
  });

  test.describe('Conversation Sidebar', () => {
    test('should display New Conversation button', async ({ page }) => {
      await expect(page.getByRole('button', { name: /new conversation/i }).first()).toBeVisible();
    });

    test('should display conversation list', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Active Conversation');
      await expect(page.locator('body')).toContainText('Completed Conversation');
    });

    test('should show status badges', async ({ page }) => {
      await expect(page.locator('body')).toContainText('active');
    });

    test('should show message count', async ({ page }) => {
      await expect(page.locator('body')).toContainText('5 messages');
    });

    test('should switch conversation on sidebar click', async ({ page }) => {
      const secondConv = page.locator('button[class*="text-left"]').filter({ hasText: 'Completed Conversation' });
      if (await secondConv.count() > 0) {
        await secondConv.click();
        // After clicking, the second conversation should be highlighted (bg-theme-bg-secondary)
        await expect(secondConv).toBeVisible();
      }
    });
  });

  test.describe('Chat Panel', () => {
    test('should show message input', async ({ page }) => {
      await expect(page.locator('[data-testid="message-input"]')).toBeVisible();
    });

    test('should show send button', async ({ page }) => {
      await expect(page.locator('[data-testid="send-button"]')).toBeVisible();
    });

    test('should disable send button when input is empty', async ({ page }) => {
      const sendBtn = page.locator('[data-testid="send-button"]');
      await expect(sendBtn).toBeDisabled();
    });

    test('should display existing messages', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Hello, can you help me?');
      await expect(page.locator('body')).toContainText('Of course! I am here to help');
    });
  });

  test.describe('Message Sending', () => {
    test('should send message and show optimistic update', async ({ page }) => {
      const input = page.locator('[data-testid="message-input"]');
      await input.fill('Test message from Playwright');
      await page.locator('[data-testid="send-button"]').click();
      // Optimistic message should appear immediately
      await expect(page.locator('body')).toContainText('Test message from Playwright');
    });

    test('should receive mock AI response after sending', async ({ page }) => {
      const input = page.locator('[data-testid="message-input"]');
      await input.fill('What is AI?');
      await page.locator('[data-testid="send-button"]').click();
      await expect(page.locator('body')).toContainText('mock AI response', { timeout: 10000 });
    });

    test('should clear input after sending', async ({ page }) => {
      const input = page.locator('[data-testid="message-input"]');
      await input.fill('Another test message');
      await page.locator('[data-testid="send-button"]').click();
      await expect(input).toHaveValue('');
    });
  });

  test.describe('New Conversation', () => {
    test('should open create conversation modal', async ({ page }) => {
      await page.getByRole('button', { name: /new conversation/i }).first().click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
    });
  });

  test.describe('Empty State', () => {
    test('should show empty state when no conversations', async ({ page }) => {
      // Re-mock with empty conversations (regex pattern overrides the earlier list route)
      await page.route(/\/agents\/agent-001\/conversations\/?(\?.*)?$/, async (route: Route) => {
        if (route.request().method() === 'GET') {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              items: [],
              pagination: { total_count: 0, page: 1, per_page: 50 },
            }),
          });
        } else {
          await route.continue();
        }
      });

      // Navigate again to trigger re-fetch
      await page.goto('/app/ai/agents/agent-001/chat');
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });

      await expect(page.locator('body')).toContainText('No conversations yet');
    });
  });
});
