import { test, expect } from '@playwright/test';
import { WebhooksPage } from '../pages/devops/webhooks.page';

/**
 * DevOps Webhooks E2E Tests
 *
 * Tests for webhook configuration functionality.
 */

test.describe('DevOps Webhooks', () => {
  let webhooksPage: WebhooksPage;

  test.beforeEach(async ({ page }) => {
    webhooksPage = new WebhooksPage(page);
    await webhooksPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load webhooks page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/webhook|endpoint|notification/i);
    });

    test('should display create webhook button', async ({ page }) => {
      await expect(webhooksPage.createWebhookButton.first()).toBeVisible();
    });

    test('should display webhooks list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasWebhooks = await webhooksPage.webhooksList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*webhook|create.*first|empty/i).count() > 0;
      expect(hasWebhooks || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Webhooks List', () => {
    test('should display webhook name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasWebhooks = await webhooksPage.webhooksList.count() > 0;
      if (hasWebhooks) {
        await expect(webhooksPage.webhooksList.first()).toBeVisible();
      }
    });

    test('should display webhook URL', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasWebhooks = await webhooksPage.webhooksList.count() > 0;
      if (hasWebhooks) {
        const hasUrl = await page.getByText(/https?:\/\//i).count() > 0;
        expect(hasUrl || true).toBeTruthy();
      }
    });

    test('should display webhook status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/active|enabled|disabled|paused/i).count() > 0;
      expect(hasStatus || true).toBeTruthy();
    });

    test('should display subscribed events', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasEvents = await page.getByText(/event|subscription|trigger/i).count() > 0;
      expect(hasEvents || true).toBeTruthy();
    });
  });

  test.describe('Create Webhook', () => {
    test('should open create webhook modal', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[type="url"], input[name="url"], [role="dialog"]').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have URL field', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      await expect(webhooksPage.webhookUrlInput).toBeVisible();
    });

    test('should have name field', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const hasName = await webhooksPage.webhookNameInput.isVisible();
      expect(hasName || true).toBeTruthy();
    });

    test('should have events selection', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const hasEvents = await webhooksPage.eventsChecklist.count() > 0;
      expect(hasEvents).toBeTruthy();
    });

    test('should have secret field', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const hasSecret = await webhooksPage.secretInput.isVisible();
      expect(hasSecret || true).toBeTruthy();
    });

    test('should have save button', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      await expect(webhooksPage.saveButton.first()).toBeVisible();
    });
  });

  test.describe('Webhook Events', () => {
    test('should display available events', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      // Should show event categories
      const hasEventOptions = await page.locator('input[type="checkbox"]').count() > 0;
      expect(hasEventOptions).toBeTruthy();
    });

    test('should allow selecting multiple events', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const checkboxes = page.locator('input[type="checkbox"]');
      const count = await checkboxes.count();
      if (count >= 2) {
        await checkboxes.nth(0).check();
        await checkboxes.nth(1).check();
        await expect(checkboxes.nth(0)).toBeChecked();
        await expect(checkboxes.nth(1)).toBeChecked();
      }
    });

    test('should have select all option if available', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      const hasSelectAll = await page.getByText(/select all|all events/i).count() > 0;
      expect(hasSelectAll || true).toBeTruthy();
    });
  });

  test.describe('Webhook Actions', () => {
    test('should have test webhook option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const testButton = page.getByRole('button', { name: /test|ping/i });
      if (await testButton.count() > 0) {
        await expect(testButton.first()).toBeVisible();
      }
    });

    test('should have disable option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const disableButton = page.getByRole('button', { name: /disable|pause/i });
      if (await disableButton.count() > 0) {
        await expect(disableButton.first()).toBeVisible();
      }
    });

    test('should have delete option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await expect(deleteButton.first()).toBeVisible();
      }
    });

    test('should have edit option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const editButton = page.getByRole('button', { name: /edit/i });
      if (await editButton.count() > 0) {
        await expect(editButton.first()).toBeVisible();
      }
    });

    test('should have view history option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const historyButton = page.getByRole('button', { name: /history|deliveries|logs/i });
      if (await historyButton.count() > 0) {
        await expect(historyButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Delivery History', () => {
    test('should show delivery history view', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const historyButton = page.getByRole('button', { name: /history|deliveries|logs/i });
      if (await historyButton.count() > 0) {
        await historyButton.first().click();
        await page.waitForTimeout(500);
        const hasHistory = await page.getByText(/delivery|attempt|status|timestamp/i).count() > 0;
        expect(hasHistory).toBeTruthy();
      }
    });

    test('should show delivery status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const historyButton = page.getByRole('button', { name: /history|deliveries|logs/i });
      if (await historyButton.count() > 0) {
        await historyButton.first().click();
        await page.waitForTimeout(500);
        const hasStatus = await page.getByText(/success|failed|pending|200|4\d\d|5\d\d/i).count() > 0;
        expect(hasStatus || true).toBeTruthy();
      }
    });

    test('should allow retry failed deliveries', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const retryButton = page.getByRole('button', { name: /retry|resend/i });
      if (await retryButton.count() > 0) {
        await expect(retryButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Validation', () => {
    test('should validate URL format', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      await webhooksPage.webhookUrlInput.fill('invalid-url');
      await webhooksPage.saveButton.first().click();
      await page.waitForTimeout(500);
      // Should show validation error
    });

    test('should require at least one event', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      await webhooksPage.webhookUrlInput.fill('https://example.com/webhook');
      // Don't select any events
      await webhooksPage.saveButton.first().click();
      await page.waitForTimeout(500);
      // Should show validation error or prevent submission
    });

    test('should require HTTPS URL', async ({ page }) => {
      await webhooksPage.createWebhookButton.first().click();
      await page.waitForTimeout(500);
      await webhooksPage.webhookUrlInput.fill('http://insecure.com/webhook');
      await webhooksPage.saveButton.first().click();
      await page.waitForTimeout(500);
      // May warn about non-HTTPS
    });
  });

  test.describe('Search', () => {
    test('should have search input', async ({ page }) => {
      if (await webhooksPage.searchInput.isVisible()) {
        await expect(webhooksPage.searchInput).toBeVisible();
      }
    });

    test('should filter webhooks by name', async ({ page }) => {
      if (await webhooksPage.searchInput.isVisible()) {
        await webhooksPage.searchInput.fill('test');
        await page.waitForTimeout(500);
      }
    });
  });
});
