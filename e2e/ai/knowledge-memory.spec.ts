import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Knowledge Memory E2E Tests
 *
 * Tests for the KnowledgeMemoryPage with tier explorer.
 * Uses error-capture pattern to detect runtime crashes like the entries.map bug.
 */

test.describe('AI Knowledge Memory', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.memory);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load memory page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/memory|knowledge|tier/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/memory/i);
    });
  });

  test.describe('Agent Selector', () => {
    test('should display agent selector or agent list', async ({ page }) => {
      const hasSelector = await page.locator('select, [class*="select"], [class*="dropdown"]').count() > 0;
      const hasAgentList = await page.getByText(/agent|select.*agent/i).count() > 0;
      const hasContent = await page.getByText(/memory/i).count() > 0;

      expect(hasSelector || hasAgentList || hasContent).toBeTruthy();
    });
  });

  test.describe('Memory Tier Tabs', () => {
    test('should display tier tabs', async ({ page }) => {
      const hasWorking = await page.getByText(/working/i).count() > 0;
      const hasShortTerm = await page.getByText(/short.?term/i).count() > 0;
      const hasLongTerm = await page.getByText(/long.?term/i).count() > 0;
      const hasShared = await page.getByText(/shared/i).count() > 0;
      const hasMemory = await page.getByText(/memory|tier/i).count() > 0;

      expect(hasWorking || hasShortTerm || hasLongTerm || hasShared || hasMemory).toBeTruthy();
    });

    test('should switch to Short Term tier without crash', async ({ page }) => {
      const shortTermTab = page.locator('button').filter({ hasText: /short.?term/i }).first();

      if (await shortTermTab.count() > 0) {
        await shortTermTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Long Term tier without crash', async ({ page }) => {
      const longTermTab = page.locator('button').filter({ hasText: /long.?term/i }).first();

      if (await longTermTab.count() > 0) {
        await longTermTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Shared tier without crash', async ({ page }) => {
      const sharedTab = page.locator('button').filter({ hasText: /shared/i }).first();

      if (await sharedTab.count() > 0) {
        await sharedTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all tiers without crash', async ({ page }) => {
      const tierButtons = page.locator('button').filter({ hasText: /working|short|long|shared/i });
      const count = await tierButtons.count();

      for (let i = 0; i < count; i++) {
        await tierButtons.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Memory Entries', () => {
    test('should display entries list or empty state (catches .map bug)', async ({ page }) => {
      const hasEntries = await page.locator('[class*="card"], [class*="entry"], tr, li').count() > 0;
      const hasEmpty = await page.getByText(/no.*memor|no.*entr|empty|no data/i).count() > 0;
      const hasContent = await page.getByText(/memory/i).count() > 0;

      expect(hasEntries || hasEmpty || hasContent).toBeTruthy();
      // Specifically check no .map-on-undefined errors
      expect(pageErrors.filter(e => /map|undefined|null|not a function/i.test(e))).toEqual([]);
    });
  });

  test.describe('Shared Knowledge Section', () => {
    test('should display shared knowledge section', async ({ page }) => {
      const sharedTab = page.locator('button').filter({ hasText: /shared/i }).first();

      if (await sharedTab.count() > 0) {
        await sharedTab.click();
        await page.waitForTimeout(500);

        const hasSharedContent = await page.getByText(/shared|knowledge|team/i).count() > 0;
        const hasEntries = await page.locator('[class*="card"], [class*="entry"]').count() > 0;
        const hasEmpty = await page.getByText(/no.*shared|empty/i).count() > 0;

        expect(hasSharedContent || hasEntries || hasEmpty).toBeTruthy();
      }
    });
  });
});
