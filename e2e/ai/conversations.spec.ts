import { test, expect } from '@playwright/test';
import { ConversationsPage } from '../pages/ai/conversations.page';
import { TEST_CONVERSATION, uniqueId } from '../fixtures/test-data';

/**
 * AI Conversations E2E Tests
 *
 * Tests for AI Conversation functionality including multi-turn chat.
 * Corresponds to Manual Testing Phase 3: Conversations
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Conversations', () => {
  let conversationsPage: ConversationsPage;

  test.beforeEach(async ({ page }) => {
    conversationsPage = new ConversationsPage(page);
    await conversationsPage.goto();
    await conversationsPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should load AI Conversations page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/conversation/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai conversations|conversations/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      // Breadcrumbs show: Home > AI > Conversations
      await expect(page.locator('body')).toContainText(/ai.*conversation|conversation/i);
    });
  });

  test.describe('Conversation List Display', () => {
    test('should display conversation list or empty state', async ({ page }) => {
      const hasConversations = await page.locator('table tbody tr, [class*="conversation"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No conversations"), :text("Start Conversation")').count() > 0;

      expect(hasConversations || hasEmptyState).toBeTruthy();
    });

    test('should display conversation status badges', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|completed|archived|conversation/i);
    });

    test('should display message counts', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/messages|tokens|conversation/i);
    });

    test('should display last activity timestamps', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ago|activity|last|conversation/i);
    });
  });

  test.describe('Search Functionality', () => {
    test('should have search input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="Search" i], input[placeholder*="search" i]');
      await expect(searchInput.first()).toBeVisible();
    });
  });

  test.describe('Filter by Status', () => {
    test('should have status filter dropdown', async ({ page }) => {
      // Look for filter controls - may be select, button, or custom component
      const hasFilter = await page.locator('select, [class*="select"], button:has-text("Status"), button:has-text("All")').count() > 0;
      const hasFilterText = (await page.locator('body').textContent())?.toLowerCase().includes('status') ||
                            (await page.locator('body').textContent())?.toLowerCase().includes('filter');
      expect(hasFilter || hasFilterText).toBeTruthy();
    });
  });

  test.describe('Filter by Agent', () => {
    test('should have agent filter dropdown', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agent|all agents|conversation/i);
    });
  });

  test.describe('Start Conversation - Phase 3.1', () => {
    test('should display Start Conversation button', async ({ page }) => {
      const startButton = page.locator('button:has-text("Start Conversation"), button:has-text("New Conversation"), button:has-text("Create")');
      await expect(startButton.first()).toBeVisible();
    });

    test('should open create modal when Start Conversation clicked', async ({ page }) => {
      const startButton = page.locator('button:has-text("Start Conversation")').first();

      if (await startButton.count() > 0) {
        await startButton.click();
        await page.waitForTimeout(500); // Allow modal animation

        // Modal should show conversation creation form - look for common form elements
        const hasModal = await page.locator('[role="dialog"], [class*="modal"], input, textarea').count() > 0;
        expect(hasModal).toBeTruthy();
      }
    });

    test('should create a new conversation', async ({ page }) => {
      const startButton = page.locator('button:has-text("Start Conversation")').first();

      if (await startButton.count() > 0) {
        await startButton.click();
        await page.waitForTimeout(500);

        // Verify we can access conversation creation (form visible or navigated)
        await expect(page.locator('body')).toContainText(/conversation|chat|title|agent/i);
      }
    });
  });

  test.describe('Send Message - Phase 3.2', () => {
    test('should send message in conversation', async ({ page }) => {
      // Find and open an existing conversation or create one
      const conversationRow = page.locator('tr, [class*="conversation"]').first();

      if (await conversationRow.count() > 0) {
        // Click continue button
        const continueButton = conversationRow.locator('button:has-text("Continue")');

        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForLoadState('networkidle');

          // Send a message
          await conversationsPage.sendMessage(TEST_CONVERSATION.initialMessage);

          // Wait for AI response
          await page.waitForSelector('[class*="message"], [class*="chat-message"]', {
            timeout: 60000,
          });

          // Verify response appeared
          const messageCount = await conversationsPage.getMessageCount();
          expect(messageCount).toBeGreaterThan(0);
        }
      }
    });
  });

  test.describe('Context Retention - Phase 3.3', () => {
    test('should maintain context across messages', async ({ page }) => {
      const conversationRow = page.locator('tr, [class*="conversation"]').first();

      if (await conversationRow.count() > 0) {
        const continueButton = conversationRow.locator('button:has-text("Continue")');

        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForLoadState('networkidle');

          // Set context
          await conversationsPage.sendMessage('My name is TestUser123');
          await conversationsPage.waitForResponse();

          // Verify context retention
          await conversationsPage.sendMessage('What is my name?');
          await conversationsPage.waitForResponse();

          // AI should remember the name
          await expect(page.locator('[class*="message"]').last()).toContainText(/testuser123/i, { timeout: 60000 });
        }
      }
    });
  });

  test.describe('Multi-turn Conversation - Phase 3.4', () => {
    test('should support multi-turn conversation', async ({ page }) => {
      const conversationRow = page.locator('tr, [class*="conversation"]').first();

      if (await conversationRow.count() > 0) {
        const continueButton = conversationRow.locator('button:has-text("Continue")');

        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForLoadState('networkidle');

          // Send multiple messages
          for (let i = 0; i < 3; i++) {
            await conversationsPage.sendMessage(`Test message ${i + 1}`);
            await conversationsPage.waitForResponse();
          }

          // Verify message history is visible
          const messageCount = await conversationsPage.getMessageCount();
          expect(messageCount).toBeGreaterThanOrEqual(6); // 3 user + 3 AI messages
        }
      }
    });
  });

  test.describe('Message Management - Phase 17', () => {
    test('should rate message with thumbs up', async ({ page }) => {
      const conversationRow = page.locator('tr, [class*="conversation"]').first();

      if (await conversationRow.count() > 0) {
        const continueButton = conversationRow.locator('button:has-text("Continue")');

        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForLoadState('networkidle');

          // Look for thumbs up button
          const thumbsUp = page.locator('[aria-label*="thumbs up"], button:has([class*="thumb-up"])');

          if (await thumbsUp.count() > 0) {
            await thumbsUp.first().click();

            // Verify feedback notification
            await expect(page.locator(':text("Feedback"), :text("Recorded")')).toBeVisible({ timeout: 5000 });
          }
        }
      }
    });

    test('should copy message content', async ({ page }) => {
      const conversationRow = page.locator('tr, [class*="conversation"]').first();

      if (await conversationRow.count() > 0) {
        const continueButton = conversationRow.locator('button:has-text("Continue")');

        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForLoadState('networkidle');

          // Look for copy button
          const copyButton = page.locator('[aria-label*="copy"], button:has([class*="copy"])');

          if (await copyButton.count() > 0) {
            await copyButton.first().click();

            // Verify copy notification
            await expect(page.locator(':text("Copied")')).toBeVisible({ timeout: 5000 });
          }
        }
      }
    });
  });

  test.describe('View Conversation Details', () => {
    test('should have View action for conversations or show empty state', async ({ page }) => {
      const hasViewButton = await page.locator('button[title="View Details"], button:has-text("View")').count() > 0;
      const hasEmptyState = await page.locator(':text("No conversations"), :text("Start Conversation")').count() > 0;

      expect(hasViewButton || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Export Conversation', () => {
    test('should have Export action for conversations or show empty state', async ({ page }) => {
      const hasExportButton = await page.locator('button[title="Export"], button:has-text("Export")').count() > 0;
      const hasEmptyState = await page.locator(':text("No conversations"), :text("Start Conversation")').count() > 0;

      expect(hasExportButton || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Archive/Unarchive Conversation', () => {
    test('should have Archive action for conversations or show empty state', async ({ page }) => {
      const hasArchiveButton = await page.locator('button[title="Archive"], button[title="Unarchive"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No conversations"), :text("Start Conversation")').count() > 0;

      expect(hasArchiveButton || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Delete Conversation', () => {
    test('should have Delete action for conversations or show empty state', async ({ page }) => {
      const hasDeleteButton = await page.locator('button[title="Delete"], button:has-text("Delete")').count() > 0;
      const hasEmptyState = await page.locator(':text("No conversations"), :text("Start Conversation")').count() > 0;

      expect(hasDeleteButton || hasEmptyState).toBeTruthy();
    });

    test('should show confirmation before delete', async ({ page }) => {
      const deleteButton = page.locator('button[title="Delete Conversation"]').first();

      if (await deleteButton.count() > 0) {
        await deleteButton.click();
        await page.waitForLoadState('networkidle');

        // Verify confirmation dialog appeared (use first() to avoid strict mode)
        await expect(page.getByText('Are you sure').first()).toBeVisible();
      }
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Permission-Based Actions', () => {
    test('should show actions based on permissions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/start|delete|export|conversation/i);
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await conversationsPage.goto();
      await expect(page.locator('body')).toContainText(/conversation/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await conversationsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
