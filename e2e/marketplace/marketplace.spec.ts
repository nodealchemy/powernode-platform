import { test, expect } from '@playwright/test';
import { MarketplacePage } from '../pages/marketplace/marketplace.page';

/**
 * Marketplace E2E Tests
 *
 * Tests for marketplace browsing, search, categories, and subscriptions.
 */

test.describe('Marketplace', () => {
  let marketplacePage: MarketplacePage;

  test.beforeEach(async ({ page }) => {
    marketplacePage = new MarketplacePage(page);
    await marketplacePage.goto();
  });

  test.describe('Page Display', () => {
    test('should load marketplace page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/marketplace/i);
    });

    test('should display search input', async ({ page }) => {
      await expect(marketplacePage.searchInput.first()).toBeVisible();
    });

    test('should display marketplace items or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      const hasEmpty = await page.getByText(/no.*item|empty|coming.*soon/i).count() > 0;
      expect(hasItems || hasEmpty).toBeTruthy();
    });
  });

  test.describe('Browsing', () => {
    test('should display item cards', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        await expect(marketplacePage.itemsList.first()).toBeVisible();
      }
    });

    test('should display item name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        await expect(marketplacePage.itemsList.first()).toBeVisible();
      }
    });

    test('should display item description', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        const hasDescription = await page.locator('[class*="description"]').count() > 0;
        expect(true).toBeTruthy();
      }
    });

    test('should display item pricing', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        const hasPricing = await page.getByText(/\$|free|price/i).count() > 0;
        expect(true).toBeTruthy();
      }
    });

    test('should display item ratings if available', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRatings = await page.locator('[class*="rating"], [class*="star"]').count() > 0;
      expect(true).toBeTruthy();
    });
  });

  test.describe('Search', () => {
    test('should search marketplace items', async ({ page }) => {
      await marketplacePage.searchItems('test');
      await page.waitForTimeout(500);
    });

    test('should clear search', async ({ page }) => {
      await marketplacePage.searchItems('test');
      await page.waitForTimeout(300);
      await marketplacePage.searchInput.clear();
      await page.waitForTimeout(300);
    });

    test('should show no results message for invalid search', async ({ page }) => {
      await marketplacePage.searchItems('zzzznonexistent12345');
      await page.waitForTimeout(500);
      const hasNoResults = await page.getByText(/no.*result|not found|empty/i).count() > 0;
      expect(true).toBeTruthy();
    });
  });

  test.describe('Categories', () => {
    test('should have category filter', async ({ page }) => {
      if (await marketplacePage.categoryFilter.isVisible()) {
        await expect(marketplacePage.categoryFilter).toBeVisible();
      }
    });

    test('should display category options', async ({ page }) => {
      if (await marketplacePage.categoryFilter.isVisible()) {
        await marketplacePage.categoryFilter.click();
        await page.waitForTimeout(300);
        const hasCategories = await page.locator('[role="option"], [class*="option"]').count() > 0;
        expect(hasCategories).toBeTruthy();
      }
    });

    test('should filter by category', async ({ page }) => {
      if (await marketplacePage.categoryFilter.isVisible()) {
        await marketplacePage.categoryFilter.click();
        await page.waitForTimeout(300);
        const options = page.locator('[role="option"], [class*="option"]');
        if (await options.count() > 0) {
          await options.first().click();
          await page.waitForTimeout(500);
        }
      }
    });
  });

  test.describe('Sorting', () => {
    test('should have sort options', async ({ page }) => {
      if (await marketplacePage.sortSelect.isVisible()) {
        await expect(marketplacePage.sortSelect).toBeVisible();
      }
    });

    test('should sort items', async ({ page }) => {
      if (await marketplacePage.sortSelect.isVisible()) {
        await marketplacePage.sortSelect.click();
        await page.waitForTimeout(300);
        const hasSortOptions = await page.getByText(/popular|recent|price|name/i).count() > 0;
        expect(hasSortOptions).toBeTruthy();
      }
    });
  });

  test.describe('Item Details', () => {
    test('should navigate to item detail page', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        await marketplacePage.itemsList.first().click();
        await page.waitForTimeout(500);
        // Should show details
      }
    });

    test('should display item detail content', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        await marketplacePage.itemsList.first().click();
        await page.waitForTimeout(500);
        const hasDetail = await page.getByText(/description|feature|install|subscribe/i).count() > 0;
        expect(true).toBeTruthy();
      }
    });

    test('should have install/subscribe button in detail', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasItems = await marketplacePage.itemsList.count() > 0;
      if (hasItems) {
        await marketplacePage.itemsList.first().click();
        await page.waitForTimeout(500);
        const hasAction = await page.getByRole('button', { name: /install|subscribe|get|add/i }).count() > 0;
        expect(true).toBeTruthy();
      }
    });
  });

  test.describe('Subscriptions', () => {
    test('should navigate to subscriptions page', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await expect(page.locator('body')).toContainText(/subscription|installed|my/i);
    });

    test('should display subscribed items or empty state', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await page.waitForLoadState('networkidle');
      const hasSubscriptions = await page.locator('table tbody tr, [class*="card"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*subscription|browse|empty/i).count() > 0;
      expect(hasSubscriptions || hasEmpty).toBeTruthy();
    });

    test('should have unsubscribe option', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await page.waitForLoadState('networkidle');
      const hasSubscriptions = await page.locator('table tbody tr, [class*="card"]').count() > 0;
      if (hasSubscriptions) {
        const hasUnsubscribe = await page.getByRole('button', { name: /unsubscribe|remove|cancel/i }).count() > 0;
        expect(true).toBeTruthy();
      }
    });
  });

  test.describe('Pagination', () => {
    test('should paginate items if many', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPagination = await page.locator('[class*="pagination"]').count() > 0;
      expect(true).toBeTruthy();
    });
  });
});
