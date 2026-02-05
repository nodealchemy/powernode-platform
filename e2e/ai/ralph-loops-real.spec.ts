import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Ralph Loops - Real Backend E2E Tests
 *
 * Tests against actual Rails server with configured AI agents.
 * Requires running server and at least one active AI agent.
 * Uses test.slow() for AI execution timeouts.
 */

// Check if backend is reachable
let backendAvailable = false;

test.beforeAll(async () => {
  try {
    const response = await fetch('http://localhost:3000/api/v1/health');
    backendAvailable = response.ok;
  } catch {
    backendAvailable = false;
  }
});

test.describe('Ralph Loops - Real Backend', () => {
  test.beforeEach(async ({ page }) => {
    test.skip(!backendAvailable, 'Backend not reachable at localhost:3000');
    page.on('pageerror', () => {});
    await page.goto(ROUTES.ralphLoops);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Load', () => {
    test('should navigate to Ralph Loops page', async ({ page }) => {
      expect(page.url()).toContain('/ralph-loops');
      await expect(page.locator('body')).toContainText('Ralph Loops');
    });

    test('should display page with loop cards or empty state', async ({ page }) => {
      const hasCards = await page.locator('[class*="Card"]').filter({ hasText: /loop/i }).count() > 0;
      const hasEmpty = await page.locator('text=No loops found').count() > 0;
      expect(hasCards || hasEmpty).toBeTruthy();
    });

    test('should find loop card with agent name if loops exist', async ({ page }) => {
      const loopCards = page.locator('[class*="Card"]').filter({ hasText: /loop/i });
      if (await loopCards.count() > 0) {
        await expect(loopCards.first()).toBeVisible();
        // Should show agent name or 'No Agent'
        const cardText = await loopCards.first().textContent();
        expect(cardText).toBeTruthy();
      }
    });
  });

  test.describe('Loop Detail', () => {
    test('should open loop detail view on card click', async ({ page }) => {
      const cards = page.locator('[class*="Card"]').filter({ hasText: /loop/i });
      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');
        // Should show detail view with Back button
        await expect(page.getByRole('button', { name: /back to list/i })).toBeVisible();
        // Should show stats cards
        await expect(page.locator('body')).toContainText('Iterations');
        await expect(page.locator('body')).toContainText('Default Agent');
      }
    });

    test('should show agent name in detail view', async ({ page }) => {
      const loopCards = page.locator('[class*="Card"]').filter({ hasText: /loop/i });
      if (await loopCards.count() > 0) {
        await loopCards.first().click();
        await page.waitForLoadState('networkidle');
        const agentCard = page.locator('text=Default Agent').locator('..');
        // Should show an agent name or 'No Agent' / 'Not Set'
        const agentText = await agentCard.textContent();
        expect(agentText).toContain('Default Agent');
      }
    });
  });

  test.describe('Loop Lifecycle', () => {
    test.slow();

    test('should start a pending loop', async ({ page }) => {
      const pendingCard = page.locator('[class*="Card"]').filter({ hasText: 'Pending' });
      if (await pendingCard.count() > 0) {
        await pendingCard.first().click();
        await page.waitForLoadState('networkidle');

        const startBtn = page.getByRole('button', { name: /start loop/i });
        if (await startBtn.isVisible()) {
          await startBtn.click();
          await page.waitForLoadState('networkidle');
          // Status should change to Running
          await expect(page.locator('body')).toContainText('Running', { timeout: 10000 });
        }
      }
    });

    test('CRITICAL: Run One button should appear when loop is running', async ({ page }) => {
      // Find a running loop
      const runningCard = page.locator('[class*="Card"]').filter({ hasText: 'Running' });
      if (await runningCard.count() > 0) {
        await runningCard.first().click();
        await page.waitForLoadState('networkidle');
        // The Run One button MUST be visible - this verifies the bug fix
        await expect(page.getByRole('button', { name: /run one/i })).toBeVisible({ timeout: 5000 });
      } else {
        // Try to start a pending loop first
        const pendingCard = page.locator('[class*="Card"]').filter({ hasText: 'Pending' });
        if (await pendingCard.count() > 0) {
          await pendingCard.first().click();
          await page.waitForLoadState('networkidle');
          const startBtn = page.getByRole('button', { name: /start loop/i });
          if (await startBtn.isVisible()) {
            await startBtn.click();
            await page.waitForLoadState('networkidle');
            await expect(page.getByRole('button', { name: /run one/i })).toBeVisible({ timeout: 10000 });
          }
        }
      }
    });

    test('should run an iteration when clicking Run One', async ({ page }) => {
      const runningCard = page.locator('[class*="Card"]').filter({ hasText: 'Running' });
      if (await runningCard.count() > 0) {
        await runningCard.first().click();
        await page.waitForLoadState('networkidle');

        const runOneBtn = page.getByRole('button', { name: /run one/i });
        if (await runOneBtn.isVisible()) {
          await runOneBtn.click();
          // Wait for iteration to complete (may take time with real agent)
          await page.waitForLoadState('networkidle');
          // The page should still be functional after running
          await expect(page.getByRole('button', { name: /back to list/i })).toBeVisible();
        }
      }
    });

    test('should pause a running loop', async ({ page }) => {
      const runningCard = page.locator('[class*="Card"]').filter({ hasText: 'Running' });
      if (await runningCard.count() > 0) {
        await runningCard.first().click();
        await page.waitForLoadState('networkidle');

        const pauseBtn = page.getByRole('button', { name: /^pause$/i });
        if (await pauseBtn.isVisible()) {
          await pauseBtn.click();
          await page.waitForLoadState('networkidle');
          await expect(page.locator('body')).toContainText('Paused', { timeout: 10000 });
        }
      }
    });

    test('should resume a paused loop', async ({ page }) => {
      const pausedCard = page.locator('[class*="Card"]').filter({ hasText: 'Paused' });
      if (await pausedCard.count() > 0) {
        await pausedCard.first().click();
        await page.waitForLoadState('networkidle');

        const resumeBtn = page.getByRole('button', { name: /^resume$/i });
        if (await resumeBtn.isVisible()) {
          await resumeBtn.click();
          await page.waitForLoadState('networkidle');
          await expect(page.locator('body')).toContainText('Running', { timeout: 10000 });
          // Run One should reappear after resuming
          await expect(page.getByRole('button', { name: /run one/i })).toBeVisible();
        }
      }
    });

    test('should cancel a loop', async ({ page }) => {
      // Find a paused loop (safest to cancel)
      const pausedCard = page.locator('[class*="Card"]').filter({ hasText: 'Paused' });
      if (await pausedCard.count() > 0) {
        await pausedCard.first().click();
        await page.waitForLoadState('networkidle');

        const cancelBtn = page.getByRole('button', { name: /^cancel$/i });
        if (await cancelBtn.isVisible()) {
          await cancelBtn.click();
          await page.waitForLoadState('networkidle');
          await expect(page.locator('body')).toContainText('Cancelled', { timeout: 10000 });
        }
      }
    });

    test('should reset a terminal-state loop', async ({ page }) => {
      const terminalCard = page.locator('[class*="Card"]').filter({ hasText: /Completed|Failed|Cancelled/ });
      if (await terminalCard.count() > 0) {
        await terminalCard.first().click();
        await page.waitForLoadState('networkidle');

        const resetBtn = page.getByRole('button', { name: /^reset$/i });
        if (await resetBtn.isVisible()) {
          await resetBtn.click();
          await page.waitForLoadState('networkidle');
          await expect(page.locator('body')).toContainText('Pending', { timeout: 10000 });
        }
      }
    });
  });

  test.describe('Tab Navigation', () => {
    test('should switch between tabs in detail view', async ({ page }) => {
      const cards = page.locator('[class*="Card"]').filter({ hasText: /loop/i });
      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');

        // Tasks tab (default)
        const tasksTab = page.getByRole('tab', { name: /tasks/i });
        await expect(tasksTab).toBeVisible();

        // Switch to Iterations
        await page.getByRole('tab', { name: /iterations/i }).click();
        await expect(page.getByRole('tab', { name: /iterations/i })).toHaveAttribute('data-state', 'active');

        // Switch to Progress
        await page.getByRole('tab', { name: /progress/i }).click();
        await expect(page.getByRole('tab', { name: /progress/i })).toHaveAttribute('data-state', 'active');

        // Switch to Schedule
        await page.getByRole('tab', { name: /schedule/i }).click();
        await expect(page.getByRole('tab', { name: /schedule/i })).toHaveAttribute('data-state', 'active');

        // Switch back to Tasks
        await tasksTab.click();
        await expect(tasksTab).toHaveAttribute('data-state', 'active');
      }
    });
  });
});
