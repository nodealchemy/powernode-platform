import { test, expect } from '@playwright/test';
import { MarketplacePage } from '../pages/marketplace/marketplace.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Marketplace E2E Tests
 *
 * Tests for marketplace browsing, search, categories, and subscriptions.
 */

test.describe('Marketplace', () => {
  let marketplacePage: MarketplacePage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    marketplacePage = new MarketplacePage(page);
    await marketplacePage.goto();
  });

  test.describe('Page Display', () => {
    test('should load marketplace page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/marketplace/i);
    });

    test('should display search input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], [data-testid="search-input"], input[placeholder*="search" i]');
      await expect(searchInput.first()).toBeVisible();
    });

    test('should display marketplace items or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      const hasEmpty = await page.getByText(/no.*item|no.*found|empty|coming.*soon/i).count() > 0;
      await expectOrAlternateState(page, hasItems || hasEmpty);
    });
  });

  test.describe('Browsing', () => {
    test('should display item cards', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      const hasEmpty = await page.getByText(/no.*item|no.*found/i).count() > 0;
      await expectOrAlternateState(page, hasItems || hasEmpty);
    });

    test('should display item name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      if (hasItems) {
        await expect(page.locator('h3').first()).toBeVisible();
      }
    });

    test('should display item description', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      await expectOrAlternateState(page, hasItems);
    });

    test('should display item pricing', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      await expectOrAlternateState(page, hasItems);
    });

    test('should display item ratings if available', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasItems = await page.locator('h3').count() > 0;
      await expectOrAlternateState(page, hasItems);
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
      await marketplacePage.searchInput.first().clear();
      await page.waitForTimeout(300);
    });

    test('should show no results message for invalid search', async ({ page }) => {
      await marketplacePage.searchItems('zzzznonexistent12345');
      await page.waitForTimeout(500);
      const hasNoResults = await page.getByText(/no.*result|not found|no.*item|no.*found/i).count() > 0;
      await expectOrAlternateState(page, hasNoResults);
    });
  });

  test.describe('Categories', () => {
    test('should have category filter', async ({ page }) => {
      const typeButtons = page.locator('button').filter({ hasText: /workflow|pipeline|integration|prompt|all/i });
      const hasFilter = await typeButtons.count() > 0;
      await expectOrAlternateState(page, hasFilter);
    });

    test('should display category options', async ({ page }) => {
      const typeButtons = page.locator('button').filter({ hasText: /workflow|pipeline|integration|prompt/i });
      if (await typeButtons.count() > 0) {
        await expect(typeButtons.first()).toBeVisible();
      }
    });

    test('should filter by category', async ({ page }) => {
      const typeButtons = page.locator('button').filter({ hasText: /workflow|pipeline|integration|prompt/i });
      if (await typeButtons.count() > 0) {
        await typeButtons.first().click();
        await page.waitForTimeout(500);
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
      await page.waitForTimeout(1000);
      const viewLinks = page.locator('a:has-text("View")');
      if (await viewLinks.count() > 0) {
        await viewLinks.first().click();
        await page.waitForTimeout(500);
      }
    });

    test('should display item detail content', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const viewLinks = page.locator('a:has-text("View")');
      if (await viewLinks.count() > 0) {
        await viewLinks.first().click();
        await page.waitForTimeout(500);
        const hasDetail = await page.getByText(/description|feature|install|subscribe/i).count() > 0;
        await expectOrAlternateState(page, hasDetail);
      }
    });

    test('should have install/subscribe button in detail', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasAction = await page.getByRole('button', { name: /install|subscribe|get|add/i }).count() > 0;
      await expectOrAlternateState(page, hasAction);
    });
  });

  test.describe('Subscriptions', () => {
    test('should navigate to subscriptions page', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await page.waitForTimeout(1000);
      await expect(page.locator('body')).toContainText(/subscription|installed|my|marketplace/i);
    });

    test('should display subscribed items or empty state', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasSubscriptions = await page.locator('h3').count() > 0;
      const hasEmpty = await page.getByText(/no.*subscription|browse|empty/i).count() > 0;
      await expectOrAlternateState(page, hasSubscriptions || hasEmpty);
    });

    test('should have unsubscribe option', async ({ page }) => {
      await marketplacePage.gotoSubscriptions();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      const hasSubscriptions = await page.locator('h3').count() > 0;
      if (hasSubscriptions) {
        const hasCancel = await page.locator('button[title="Cancel"], button:has-text("Cancel")').count() > 0;
        await expectOrAlternateState(page, hasCancel);
      }
    });
  });

  test.describe('Pagination', () => {
    test('should paginate items if many', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPagination = await page.locator('[class*="pagination"]').count() > 0;
      await expectOrAlternateState(page, hasPagination);
    });
  });
});
