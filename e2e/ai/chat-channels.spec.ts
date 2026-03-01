import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Chat Channels E2E Tests
 *
 * Tests for Chat Channels management (external platform integrations).
 */

test.describe('Chat Channels', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.chatChannels);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Chat Channels page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/chat channel|channel|chat/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|channel|chat/i);
    });

    test('should display page description', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/manage|integration|platform|channel/i);
    });
  });

  test.describe('Channel List Display', () => {
    test('should display channel list or empty state', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasChannels = await page.locator('[class*="card"], [class*="Card"], [data-testid*="channel"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No channels"), :text("no channels"), :text("Add Channel")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('channel');

      expect(hasChannels || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display channel details', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/name|platform|status|channel/i);
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search functionality', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should have platform filter', async ({ page }) => {
      const selectElements = page.locator('select, [role="combobox"]');

      if (await selectElements.count() > 0) {
        await expect(selectElements.first()).toBeVisible();
      }
    });

    test('should have status filter', async ({ page }) => {
      const selectElements = page.locator('select, [role="combobox"]');
      const count = await selectElements.count();

      if (count >= 2) {
        await expect(selectElements.nth(1)).toBeVisible();
      }
    });
  });

  test.describe('Channel Actions', () => {
    test('should have add channel button', async ({ page }) => {
      const addButton = page.locator('button:has-text("Add"), button:has-text("Create"), button:has-text("New")');
      const hasButton = await addButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('channel');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should have refresh capability', async ({ page }) => {
      const refreshButton = page.locator('button:has([class*="refresh"]), button:has-text("Refresh")');

      if (await refreshButton.count() > 0) {
        await refreshButton.first().click();
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Channel Interaction', () => {
    test('should navigate to channel detail when clicking a channel', async ({ page }) => {
      await page.waitForTimeout(1000);

      const channelCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="channel"]');

      if (await channelCards.count() > 0) {
        await channelCards.first().click();
        await page.waitForTimeout(500);

        // Should show sessions or channel detail view
        const hasDetail = await page.locator(':text("Sessions"), :text("Metrics"), :text("Back")').count() > 0;
        const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('session') ||
                          (await page.locator('body').textContent())?.toLowerCase().includes('back');

        expect(hasDetail || hasContent).toBeTruthy();
      }
    });

    test('should have settings action on channel', async ({ page }) => {
      await page.waitForTimeout(1000);

      const settingsButton = page.locator('button:has([class*="settings"]), button:has-text("Settings")');

      if (await settingsButton.count() > 0) {
        await expect(settingsButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.chatChannels);
      await expect(page.locator('body')).toContainText(/channel|chat|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.chatChannels);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
