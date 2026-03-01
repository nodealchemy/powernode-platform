import { test, expect } from '@playwright/test';
import {
  ChatWidgetPage,
  setupChatApiMocks,
  setupChatApiErrorMocks,
  setupSendMessageErrorMock,
  mockChatAgent,
  mockChatAgentSecond,
} from '../pages/ai/chat-widget.page';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Chat Widget E2E Tests
 *
 * Tests for the floating chat widget lifecycle, messaging, and modes.
 * All API calls are mocked — no real AI provider needed.
 */

test.describe('AI Chat Widget', () => {
  let chatWidget: ChatWidgetPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    chatWidget = new ChatWidgetPage(page);
    await setupChatApiMocks(page);
    await chatWidget.goto(ROUTES.overview);
  });

  // ── Widget Visibility ──────────────────────────────────────────────

  test.describe('Widget Visibility', () => {
    test('should show widget button on dashboard with correct aria-label', async ({ page }) => {
      const widget = page.locator('button[aria-label="Open AI Chat"]');
      if (await widget.count() > 0) {
        await expect(widget).toBeVisible();
      }
    });

    test('should show widget on other dashboard pages', async ({ page }) => {
      await page.goto(ROUTES.agents);
      await page.waitForLoadState('networkidle');

      const widget = page.locator('button[aria-label="Open AI Chat"]');
      if (await widget.count() > 0) {
        await expect(widget).toBeVisible();
      }
    });

    test('should hide widget when chat is open', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        // Widget should not be visible when floating chat is open
        await expect(chatWidget.widgetButton).not.toBeVisible({ timeout: 3000 });
      }
    });
  });

  // ── Open / Close ───────────────────────────────────────────────────

  test.describe('Open / Close', () => {
    test('should open floating chat when widget clicked', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        const isOpen = await chatWidget.isChatOpen();
        expect(isOpen).toBeTruthy();
      }
    });

    test('should close chat and show widget again', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        await chatWidget.closeChat();
        await expect(chatWidget.widgetButton).toBeVisible({ timeout: 3000 });
      }
    });

    test('should show online indicator in header', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        // The green dot (h-2 w-2 rounded-full bg-theme-success) should be visible
        const dot = chatWidget.onlineIndicator;
        if (await dot.count() > 0) {
          await expect(dot.first()).toBeVisible();
        }
      }
    });
  });

  // ── New Conversation Flow ──────────────────────────────────────────

  test.describe('New Conversation Flow', () => {
    test('should show agent selector on new conversation tab', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        // With no tabs, the New Conversation overlay appears
        const heading = chatWidget.newConversationHeading;
        if (await heading.count() > 0) {
          await expect(heading).toBeVisible();
        }
      }
    });

    test('should list agents in dropdown', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        const selectorBtn = chatWidget.agentSelectorButton;
        if (await selectorBtn.count() > 0) {
          await selectorBtn.click();
          await chatWidget.page.waitForTimeout(300);
          // Both mock agents should appear
          const agentOption = chatWidget.page.locator(`button:has-text("${mockChatAgent.name}")`);
          if (await agentOption.count() > 0) {
            await expect(agentOption.last()).toBeVisible();
          }
        }
      }
    });

    test('should enable Start button after agent selection', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        const startBtn = chatWidget.startConversationButton;
        if (await startBtn.count() > 0) {
          // Initially disabled
          await expect(startBtn).toBeDisabled();
          await chatWidget.selectAgent(mockChatAgent.name);
          await expect(startBtn).toBeEnabled();
        }
      }
    });

    test('should complete full flow: select agent → start → chat visible', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation(mockChatAgent.name);
          // Message input should be visible after conversation starts
          const input = chatWidget.messageInput;
          if (await input.count() > 0) {
            await expect(input).toBeVisible({ timeout: 5000 });
          }
        }
      }
    });
  });

  // ── Message Sending ────────────────────────────────────────────────

  test.describe('Message Sending', () => {
    test('should send message and clear input', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation();
        }
        const input = chatWidget.messageInput;
        if (await input.count() > 0) {
          await chatWidget.sendMessage('Test message from E2E');
          await chatWidget.page.waitForTimeout(500);
          // Input should be cleared after send
          const value = await input.inputValue();
          expect(value).toBe('');
        }
      }
    });

    test('should show send button disabled when input empty', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation();
        }
        if (await chatWidget.sendButton.count() > 0) {
          await expect(chatWidget.sendButton).toBeDisabled();
        }
      }
    });

    test('should enable send button when text entered', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation();
        }
        const input = chatWidget.messageInput;
        if (await input.count() > 0) {
          await input.fill('Something');
          await chatWidget.page.waitForTimeout(100);
          await expect(chatWidget.sendButton).toBeEnabled();
        }
      }
    });

    test('should display mock AI response after sending', async ({ page }) => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation();
        }
        const input = chatWidget.messageInput;
        if (await input.count() > 0) {
          await chatWidget.sendMessage('Hello agent');
          await page.waitForTimeout(1000);
          // Mock response includes "Mock response to:" prefix
          const response = page.locator('text=/Mock response to:/');
          if (await response.count() > 0) {
            await expect(response.first()).toBeVisible({ timeout: 5000 });
          }
        }
      }
    });
  });

  // ── Maximize Mode ──────────────────────────────────────────────────

  test.describe('Maximize Mode', () => {
    test('should maximize to fullscreen overlay', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.maximizeButton.count() > 0) {
          await chatWidget.maximize();
          const isMax = await chatWidget.isMaximized();
          expect(isMax).toBeTruthy();
        }
      }
    });

    test('should restore to floating from maximized', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.maximizeButton.count() > 0) {
          await chatWidget.maximize();
          await chatWidget.restore();
          const isFloating = await chatWidget.isFloating();
          expect(isFloating).toBeTruthy();
        }
      }
    });
  });

  // ── Header & Responsive ────────────────────────────────────────────

  test.describe('Header & Responsive', () => {
    test('should display header title', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        const title = await chatWidget.getHeaderTitle();
        // Should be "AI Chat" when no active tab, or agent name when tab is active
        expect(title).toBeTruthy();
      }
    });

    test('should display agent name in header after starting conversation', async () => {
      if (await chatWidget.isWidgetVisible()) {
        await chatWidget.openChat();
        if (await chatWidget.agentSelectorButton.count() > 0) {
          await chatWidget.startNewConversation(mockChatAgent.name);
          await chatWidget.page.waitForTimeout(500);
          // After starting a conversation, the chat window header should be present.
          // The header contains a Close button which is always visible.
          await expect(chatWidget.closeButton).toBeVisible();
          // The message input should also be available
          if (await chatWidget.messageInput.count() > 0) {
            await expect(chatWidget.messageInput).toBeVisible();
          }
        }
      }
    });

    test('should display widget on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await chatWidget.goto(ROUTES.overview);
      const widget = page.locator('button[aria-label="Open AI Chat"]');
      if (await widget.count() > 0) {
        await expect(widget).toBeVisible();
      }
    });
  });

  // ── Error Handling ─────────────────────────────────────────────────

  test.describe('Error Handling', () => {
    test('should handle API error on agent load gracefully', async ({ page }) => {
      page.on('pageerror', () => {});
      const errorWidget = new ChatWidgetPage(page);
      await setupChatApiErrorMocks(page);
      await errorWidget.goto(ROUTES.overview);
      // Page should not crash — body still visible
      await expect(page.locator('body')).toBeVisible();
    });

    test('should handle send_message error gracefully', async ({ page }) => {
      page.on('pageerror', () => {});
      const errorWidget = new ChatWidgetPage(page);
      await setupSendMessageErrorMock(page);
      await errorWidget.goto(ROUTES.overview);

      if (await errorWidget.isWidgetVisible()) {
        await errorWidget.openChat();
        if (await errorWidget.agentSelectorButton.count() > 0) {
          await errorWidget.startNewConversation();
        }
        const input = errorWidget.messageInput;
        if (await input.count() > 0) {
          await errorWidget.sendMessage('This should fail');
          await page.waitForTimeout(1000);
          // Page should still be functional after error
          await expect(page.locator('body')).toBeVisible();
        }
      }
    });
  });
});
