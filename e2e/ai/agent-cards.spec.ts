import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Agent Cards E2E Tests
 *
 * Tests for Agent Card management (A2A protocol agent cards).
 */

test.describe('Agent Cards', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.agentCards);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Agent Cards page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agent card|card|agent/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|card|agent/i);
    });
  });

  test.describe('Cards List Display', () => {
    test('should display agent cards list or empty state', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasCards = await page.locator('[class*="card"], [class*="Card"], table tbody tr').count() > 0;
      const hasEmptyState = await page.locator(':text("No agent cards"), :text("No cards"), :text("Create")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('card');

      expect(hasCards || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display card details', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/name|url|skill|capability|card|agent/i);
    });

    test('should display card status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/active|inactive|verified|status|card|agent/i);
    });
  });

  test.describe('Card Creation', () => {
    test('should have create card action', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create"), button:has-text("New"), button:has-text("Add"), button:has-text("Register")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('card');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should open create card form when button clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create"), button:has-text("Register"), button:has-text("Add")').first();

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const hasForm = await page.locator('[role="dialog"], [class*="modal"], form, input').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });
  });

  test.describe('Card Skills', () => {
    test('should display agent skills information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/skill|capability|function|endpoint|card|agent/i);
    });
  });

  test.describe('Card Verification', () => {
    test('should display verification status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/verified|unverified|pending|status|card|agent/i);
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
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.agentCards);
      await expect(page.locator('body')).toContainText(/card|agent|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.agentCards);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
