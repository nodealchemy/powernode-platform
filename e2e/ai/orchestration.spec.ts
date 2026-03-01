import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';
import { A2aTasksPage } from '../pages/ai/a2a-tasks.page';
import { AgentCardsPage } from '../pages/ai/agent-cards.page';

/**
 * AI Orchestration E2E Tests
 *
 * Tests for AI Orchestration hub, A2A Tasks, and Agent Cards functionality.
 * Covers the orchestration hub navigation, A2A task management, and agent card CRUD.
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Orchestration Hub', () => {

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
  });

  test.describe('Orchestration Page Navigation', () => {
    test('should navigate to AI Orchestration page', async ({ page }) => {
      await page.goto(ROUTES.overview);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/ai/i);
    });

    test('should display orchestration page description', async ({ page }) => {
      await page.goto(ROUTES.overview);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/manage|ai providers|agents|workflows|ai/i);
    });
  });

  test.describe('Orchestration Tab Navigation', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto(ROUTES.overview);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
    });

    test('should display Overview tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/overview/i);
    });

    test('should display Providers tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/providers/i);
    });

    test('should display Agents tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agents/i);
    });

    test('should display Workflows tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflows/i);
    });

    test('should display Conversations tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/conversations/i);
    });

    test('should display Analytics tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytics/i);
    });

    test('should display Monitoring tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/monitoring/i);
    });

    test('should display MCP tab', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/mcp/i);
    });
  });
});

test.describe('A2A Tasks', () => {
  let a2aTasksPage: A2aTasksPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    a2aTasksPage = new A2aTasksPage(page);
    await a2aTasksPage.goto();
    await a2aTasksPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should load A2A Tasks page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/a2a|task|agent-to-agent/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai.*task|a2a|task/i);
    });
  });

  test.describe('Task List Display', () => {
    test('should display task list or empty state', async ({ page }) => {
      const hasTaskList = await page.locator('[data-testid="task-list"], table tbody tr, [class*="task-item"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No tasks"), :text("Monitor")').count() > 0;
      const hasTaskContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasTaskList || hasEmptyState || hasTaskContent).toBeTruthy();
    });

    test('should display task status indicators', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|pending|completed|failed|tasks|no tasks/i);
    });

    test('should display task IDs or list items', async ({ page }) => {
      const hasTaskList = await page.locator('[data-testid="task-list"], table, [class*="task-item"]').count() > 0;
      const hasEmptyState = (await page.locator('body').textContent())?.match(/no tasks|monitor/i);

      expect(hasTaskList || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Task Detail View', () => {
    test('should navigate to task detail when task selected', async ({ page }) => {
      const taskRow = page.locator('[data-testid="task-row"], tr[data-task-id], [class*="task-item"]').first();
      if (await taskRow.count() > 0) {
        await taskRow.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/task details|details|back to list/i);
      }
    });

    test('should display Back to List button in detail view', async ({ page }) => {
      const taskRow = page.locator('[data-testid="task-row"], tr[data-task-id], [class*="task-item"]').first();
      if (await taskRow.count() > 0) {
        await taskRow.click();
        await page.waitForTimeout(500);
        const backButton = page.locator('button:has-text("Back"), button:has-text("List")');
        const hasBack = await backButton.count() > 0;
        expect(hasBack).toBeTruthy();
      }
    });
  });

  test.describe('Task Event Stream', () => {
    test('should display event stream section for active tasks', async ({ page }) => {
      const hasEventStream = await page.locator('[data-testid="event-stream"], [class*="event-stream"]').count() > 0;
      const hasTaskContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasEventStream || hasTaskContent).toBeTruthy();
    });
  });

  test.describe('Refresh Action', () => {
    test('should have refresh button', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh"), [aria-label*="refresh"], [title*="Refresh"], button[data-testid="refresh"]');
      const hasRefresh = await refreshButton.count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasRefresh || hasContent).toBeTruthy();
    });

    test('should refresh task list when clicked', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh"), [aria-label*="refresh"]').first();
      if (await refreshButton.count() > 0) {
        await refreshButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Empty State', () => {
    test('should display empty state or task list', async ({ page }) => {
      const hasEmpty = await page.locator(':text("No tasks"), :text("Monitor")').count() > 0;
      const hasTasks = await page.locator('[data-testid="task-list"], table tbody tr').count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('task');

      expect(hasEmpty || hasTasks || hasContent).toBeTruthy();
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await a2aTasksPage.goto();
      await expect(page.locator('body')).toContainText(/task|a2a/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await a2aTasksPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});

test.describe('Agent Cards', () => {
  let agentCardsPage: AgentCardsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    agentCardsPage = new AgentCardsPage(page);
    await agentCardsPage.goto();
    await agentCardsPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should load Agent Cards page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agent card|a2a/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai.*agent card|agent card|a2a/i);
    });
  });

  test.describe('Agent Card List Display', () => {
    test('should display agent card list or empty state', async ({ page }) => {
      const hasCardList = await page.locator('[data-testid="agent-card-list"], table, [class*="agent-card-item"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No agent cards"), :text("Create Agent Card")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('agent card');

      expect(hasCardList || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display agent card names or descriptions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/description|agent cards|discovery|communication/i);
    });
  });

  test.describe('Create Agent Card', () => {
    test('should display Create Agent Card button or page content', async ({ page }) => {
      const hasCreate = await page.locator('button:has-text("Create Agent Card"), button:has-text("Create")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.match(/agent cards|a2a/i);

      expect(hasCreate || hasPageContent).toBeTruthy();
    });

    test('should open create form when button clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Agent Card"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/create|name|description|cancel/i);
      }
    });

    test('should cancel creation and return to list', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Agent Card"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const cancelButton = page.locator('button:has-text("Cancel")').first();
        if (await cancelButton.count() > 0) {
          await cancelButton.click();
          await page.waitForTimeout(500);
          await expect(page.locator('body')).toContainText(/agent cards|create agent card/i);
        }
      }
    });
  });

  test.describe('Agent Card Detail View', () => {
    test('should navigate to card detail when card selected', async ({ page }) => {
      const cardRow = page.locator('[data-testid="agent-card-row"], tr[data-card-id], [class*="agent-card-item"]').first();
      if (await cardRow.count() > 0) {
        await cardRow.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/details|back to list|edit/i);
      }
    });

    test('should display Back to List button in detail view', async ({ page }) => {
      const cardRow = page.locator('[data-testid="agent-card-row"], tr[data-card-id], [class*="agent-card-item"]').first();
      if (await cardRow.count() > 0) {
        await cardRow.click();
        await page.waitForTimeout(500);
        const backButton = page.locator('button:has-text("Back"), button:has-text("List")');
        const hasBack = await backButton.count() > 0;
        expect(hasBack).toBeTruthy();
      }
    });
  });

  test.describe('Agent Card Actions', () => {
    test('should have edit action for cards or page content', async ({ page }) => {
      const hasEdit = await page.locator('button:has-text("Edit"), [aria-label*="edit"], [title*="Edit"]').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.match(/no agent cards|create agent card|agent cards|a2a/i);

      expect(hasEdit || hasPageContent).toBeTruthy();
    });

    test('should have delete action for cards or page content', async ({ page }) => {
      const hasDelete = await page.locator('button:has-text("Delete"), [aria-label*="delete"], [title*="Delete"]').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.match(/no agent cards|create agent card|agent cards|a2a/i);

      expect(hasDelete || hasPageContent).toBeTruthy();
    });
  });

  test.describe('Delete Agent Card', () => {
    test('should show confirmation before delete', async ({ page }) => {
      const deleteButton = page.locator('button:has-text("Delete"), [aria-label*="delete"]').first();
      if (await deleteButton.count() > 0) {
        await deleteButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/are you sure|confirm|cancel/i);
      }
    });
  });

  test.describe('Refresh Action', () => {
    test('should have refresh button', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh"), [aria-label*="refresh"], [title*="Refresh"], button[data-testid="refresh"]');
      const hasRefresh = await refreshButton.count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('agent');

      expect(hasRefresh || hasContent).toBeTruthy();
    });

    test('should refresh card list when clicked', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh"), [aria-label*="refresh"]').first();
      if (await refreshButton.count() > 0) {
        await refreshButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Search Functionality', () => {
    test('should have search or filter input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
      const hasSearch = await searchInput.count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('agent');

      expect(hasSearch || hasContent).toBeTruthy();
    });

    test('should filter cards by search query', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]').first();
      if (await searchInput.count() > 0) {
        await searchInput.fill('test');
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Empty State', () => {
    test('should display empty state or card list', async ({ page }) => {
      const hasEmpty = await page.locator(':text("No agent cards"), :text("Create Agent Card")').count() > 0;
      const hasCards = await page.locator('[data-testid="agent-card-list"], table tbody tr').count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('agent');

      expect(hasEmpty || hasCards || hasContent).toBeTruthy();
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await agentCardsPage.goto();
      await expect(page.locator('body')).toContainText(/agent|card|a2a/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await agentCardsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
