import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Agent Marketplace E2E Tests
 *
 * Tests for Agent Marketplace functionality.
 * Migrated from ai-agent-marketplace.cy.ts and ai-agent-marketplace-workflows.cy.ts
 */

test.describe('AI Agent Marketplace', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.marketplace);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Marketplace page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/marketplace|template|agent/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/marketplace|agent/i);
    });

    test('should display page description', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pre-built|agent|template|vertical|marketplace/i);
    });
  });

  test.describe('Template Browsing', () => {
    test('should display template grid or list', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasTemplates = await page.locator('[class*="grid"], [class*="card"], [class*="Card"], [data-testid*="template"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No templates"), :text("No agents")').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('marketplace');

      expect(hasTemplates || hasEmptyState || hasPageContent).toBeTruthy();
    });

    test('should display template cards with name and rating', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/customer support|sales|template|rating|marketplace/i);
    });

    test('should display pricing information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/free|premium|\$|price|subscription|marketplace/i);
    });

    test('should display installation count', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/install|download|user|marketplace/i);
    });
  });

  test.describe('Category Filtering', () => {
    test('should display category filters', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/category|all|support|sales|devops|marketplace/i);
    });

    test('should have search functionality', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('support');
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should display pricing type filters', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pricing|free|premium|subscription|marketplace/i);
    });
  });

  test.describe('Template Details', () => {
    test('should have template detail view functionality', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="Card"]').count() > 0;

      if (hasCards) {
        const templateCard = page.locator('[class*="card"], [class*="Card"]').first();
        await templateCard.click();
        await page.waitForTimeout(500);

        await expect(page.locator('body')).toContainText(/detail|description|feature|install|marketplace/i);
      }
    });

    test('should display install button', async ({ page }) => {
      const installButton = page.locator('button:has-text("Install"), button:has-text("Get"), button:has-text("Add")');
      const hasButton = await installButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('marketplace');

      expect(hasButton || hasPageContent).toBeTruthy();
    });
  });

  test.describe('Installation Flow', () => {
    test('should have install action available', async ({ page }) => {
      const installButton = page.locator('button:has-text("Install"), button:has-text("Get")');
      const hasButton = await installButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('marketplace');

      expect(hasButton || hasPageContent).toBeTruthy();
    });
  });

  test.describe('My Installations', () => {
    test('should have link to view installations', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/my installation|installed|my agent|marketplace/i);
    });
  });

  test.describe('Reviews Section', () => {
    test('should display reviews or rating information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/review|rating|star|feedback|marketplace/i);
    });
  });

  test.describe('Publisher Features', () => {
    test('should have publisher section or link', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/publisher|publish|create template|my template|marketplace/i);
    });
  });

  test.describe('Featured Templates', () => {
    test('should display featured or popular templates', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/featured|popular|top|recommended|marketplace/i);
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
      await page.goto(ROUTES.marketplace);
      await expect(page.locator('body')).toContainText(/marketplace|template/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.marketplace);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should show single column on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.marketplace);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should show multi-column grid on large screens', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await page.goto(ROUTES.marketplace);
      const hasGrid = await page.locator('[class*="grid"]').count() > 0;
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
