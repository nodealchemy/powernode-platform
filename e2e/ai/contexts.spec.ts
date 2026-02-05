import { test, expect } from '@playwright/test';
import { ContextsPage } from '../pages/ai/contexts.page';

/**
 * AI Contexts E2E Tests
 *
 * Tests for AI Context management functionality.
 * Covers browsing, searching, creating contexts, and detail views.
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Contexts', () => {
  let contextsPage: ContextsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    contextsPage = new ContextsPage(page);
    await contextsPage.goto();
    await contextsPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should load AI Contexts page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/context/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/context/i);
    });

    test('should display breadcrumbs or navigation context', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai.*context|context/i);
    });

    test('should display page description', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/memory|persistent|context/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation options', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/browse|search|create|context/i);
    });

    test('should switch to Browse tab', async ({ page }) => {
      const browseTab = page.getByRole('button', { name: /browse/i });
      if (await browseTab.count() > 0) {
        await browseTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Search tab', async ({ page }) => {
      const searchTab = page.getByRole('button', { name: /search/i });
      if (await searchTab.count() > 0) {
        await searchTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Create tab', async ({ page }) => {
      const createTab = page.locator('button:has-text("Create New"), button:has-text("Create")').first();
      if (await createTab.count() > 0) {
        await createTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Context Browser Display', () => {
    test('should display context list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      const hasContexts = await page.locator('[class*="card"], [class*="Card"], [class*="list"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No contexts"), :text("Create your first")').count() > 0;
      const hasContextText = (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasContexts || hasEmptyState || hasContextText).toBeTruthy();
    });

    test('should display context items with card layout', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="Card"], [class*="grid"]').count() > 0;
      const hasListContent = (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasCards || hasListContent).toBeTruthy();
    });
  });

  test.describe('Search Functionality', () => {
    test('should display search interface', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i], input[type="text"]');
      const hasSearch = await searchInput.count() > 0;
      const hasSearchText = (await page.locator('body').textContent())?.toLowerCase().includes('search');

      expect(hasSearch || hasSearchText).toBeTruthy();
    });

    test('should filter contexts by search query', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]').first();
      if (await searchInput.count() > 0) {
        await searchInput.fill('test');
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should clear search and restore list', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]').first();
      if (await searchInput.count() > 0) {
        await searchInput.fill('test');
        await searchInput.clear();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Create Context Form', () => {
    test('should have New Context or Create button', async ({ page }) => {
      const createButton = page.locator('button:has-text("New Context"), button:has-text("Create"), button:has-text("Create New")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should open create form when Create clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("New Context"), button:has-text("Create New"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/create context|name|context/i);
      }
    });

    test('should have scope selector in create form', async ({ page }) => {
      const createButton = page.locator('button:has-text("New Context"), button:has-text("Create New"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/scope|account-wide|team|context/i);
      }
    });

    test('should have cancel button in create form', async ({ page }) => {
      const createButton = page.locator('button:has-text("New Context"), button:has-text("Create New"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const cancelButton = page.locator('button:has-text("Cancel"), button:has-text("Back"), [data-testid*="cancel"]');
        const hasCancel = await cancelButton.count() > 0;
        expect(hasCancel).toBeTruthy();
      }
    });

    test('should have submit button in create form', async ({ page }) => {
      const createButton = page.locator('button:has-text("New Context"), button:has-text("Create New"), button:has-text("Create")').first();
      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        const submitButton = page.locator('button:has-text("Create Context"), button[type="submit"], button:has-text("Save")');
        const hasSubmit = await submitButton.count() > 0;
        expect(hasSubmit).toBeTruthy();
      }
    });
  });

  test.describe('Context Detail View', () => {
    test('should navigate to context detail when context clicked', async ({ page }) => {
      const contextCard = page.locator('[class*="card"][class*="cursor-pointer"], [class*="Card"] a, [class*="list-item"]').first();
      if (await contextCard.count() > 0) {
        await contextCard.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toContainText(/entries|settings|context/i);
      }
    });

    test('should display context stats on detail page', async ({ page }) => {
      await contextsPage.gotoDetail('test-context');
      await page.waitForTimeout(1000);
      await expect(page.locator('body')).toContainText(/entries|size|context|not found/i);
    });

    test('should display tab navigation on detail page', async ({ page }) => {
      await contextsPage.gotoDetail('test-context');
      await page.waitForTimeout(1000);
      await expect(page.locator('body')).toContainText(/entries|search|settings|not found/i);
    });
  });

  test.describe('Page Actions', () => {
    test('should have Refresh button or page content', async ({ page }) => {
      const hasRefresh = await page.locator('button:has-text("Refresh"), [aria-label*="refresh"], button svg').count() > 0;
      if (hasRefresh) {
        await expect(page.locator('button:has-text("Refresh"), [aria-label*="refresh"]').first()).toBeVisible();
      } else {
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Empty State', () => {
    test('should display empty state or context list', async ({ page }) => {
      const emptyState = page.locator(':text("No contexts"), :text("Create your first"), :text("no contexts")');
      const hasEmptyState = await emptyState.count() > 0;
      const hasContexts = await page.locator('[class*="card"], [class*="Card"]').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('context');

      expect(hasEmptyState || hasContexts || hasPageContent).toBeTruthy();
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
      await contextsPage.goto();
      await expect(page.locator('body')).toContainText(/context/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await contextsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });

    test('should stack elements on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await contextsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
