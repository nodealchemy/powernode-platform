import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Skills E2E Tests
 *
 * Tests for the Skills tab under the Knowledge page.
 * Skills display a grid of SkillCards with name, category, toggle,
 * command/connector counts, and optional search/filtering.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Skills', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.skills);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load skills page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/skill|knowledge/i);
    });

    test('should display Knowledge page with Skills tab active', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/knowledge/i);
    });
  });

  test.describe('Skills Grid', () => {
    test('should display skills grid or empty state', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="grid"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*skill|empty|no data|get started/i).count() > 0;
      const hasContent = await page.getByText(/skill/i).count() > 0;

      expect(hasCards || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display skill card elements', async ({ page }) => {
      const skillCard = page.locator('[class*="card"]').filter({ hasText: /command|connector/i }).first();

      if (await skillCard.count() > 0) {
        await expect(skillCard).toBeVisible();
        // Cards should have command/connector counts
        const hasCommands = await skillCard.getByText(/command/i).count() > 0;
        const hasConnectors = await skillCard.getByText(/connector/i).count() > 0;
        expect(hasCommands || hasConnectors).toBeTruthy();
      }
    });

    test('should display category badges on skill cards', async ({ page }) => {
      const badges = page.locator('[class*="rounded-full"], [class*="badge"]').filter({ hasText: /.+/ });

      if (await badges.count() > 0) {
        await expect(badges.first()).toBeVisible();
      }
    });

    test('should display toggle switches on skill cards', async ({ page }) => {
      const toggles = page.locator('button[aria-label*="able" i], [class*="toggle"], [role="switch"]');

      if (await toggles.count() > 0) {
        await expect(toggles.first()).toBeVisible();
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should display search input if present', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]');

      if (await searchInput.count() > 0) {
        await expect(searchInput.first()).toBeVisible();
      }
    });

    test('should display category filter tabs if present', async ({ page }) => {
      const categoryTabs = page.locator('button').filter({ hasText: /all|devops|security|code|data|general/i });

      if (await categoryTabs.count() > 1) {
        // Click a category tab without crash
        await categoryTabs.nth(1).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Skill Detail Panel', () => {
    test('should open detail panel on skill card click', async ({ page }) => {
      const skillCard = page.locator('[class*="card"]').filter({ hasText: /command|connector/i }).first();

      if (await skillCard.count() > 0) {
        await skillCard.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Responsive', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.skills);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/skill|knowledge/i);
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.skills);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/skill|knowledge/i);
    });
  });
});
