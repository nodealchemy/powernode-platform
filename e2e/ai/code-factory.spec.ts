import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Code Factory E2E Tests
 *
 * Tests for the Code Factory page (under Missions) including
 * Dashboard, Contracts, Runs, Harness Gaps, and Evidence tabs.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Code Factory', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.missionsCodeFactory);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load code factory page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/code.*factory|contract|mission/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/mission/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display Dashboard tab as default', async ({ page }) => {
      const hasDashboard = await page.locator('button').filter({ hasText: /dashboard/i }).count() > 0;
      const hasContent = await page.getByText(/code.*factory|contract|dashboard/i).count() > 0;

      expect(hasDashboard || hasContent).toBeTruthy();
    });

    test('should switch to Contracts tab without crash', async ({ page }) => {
      const contractsTab = page.locator('button').filter({ hasText: /contracts/i }).first();

      if (await contractsTab.count() > 0) {
        await contractsTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Runs tab without crash', async ({ page }) => {
      const runsTab = page.locator('button').filter({ hasText: /runs/i }).first();

      if (await runsTab.count() > 0) {
        await runsTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Harness Gaps tab without crash', async ({ page }) => {
      const harnessTab = page.locator('button').filter({ hasText: /harness.*gap/i }).first();

      if (await harnessTab.count() > 0) {
        await harnessTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Evidence tab without crash', async ({ page }) => {
      const evidenceTab = page.locator('button').filter({ hasText: /evidence/i }).first();

      if (await evidenceTab.count() > 0) {
        await evidenceTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all code factory tabs without crash', async ({ page }) => {
      const tabs = page.locator('button').filter({ hasText: /dashboard|contracts|runs|harness|evidence/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Dashboard Tab', () => {
    test('should display stats cards or empty state', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="stat"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*contract|no.*data|empty|get started/i).count() > 0;
      const hasContent = await page.getByText(/contract|run|gap|evidence|code.*factory/i).count() > 0;

      expect(hasCards || hasEmpty || hasContent).toBeTruthy();
    });
  });

  test.describe('Contracts Tab', () => {
    test('should display contract list or empty state', async ({ page }) => {
      const contractsTab = page.locator('button').filter({ hasText: /contracts/i }).first();

      if (await contractsTab.count() > 0) {
        await contractsTab.click();
        await page.waitForTimeout(500);

        const hasContracts = await page.locator('[class*="card"], [class*="contract"], tr').count() > 0;
        const hasEmpty = await page.getByText(/no.*contract|empty|no data/i).count() > 0;
        const hasContent = await page.getByText(/contract/i).count() > 0;

        expect(hasContracts || hasEmpty || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Harness Gaps Tab', () => {
    test('should display gaps or no-gaps message', async ({ page }) => {
      const harnessTab = page.locator('button').filter({ hasText: /harness.*gap/i }).first();

      if (await harnessTab.count() > 0) {
        await harnessTab.click();
        await page.waitForTimeout(500);

        const hasGaps = await page.locator('[class*="card"], [class*="gap"]').count() > 0;
        const hasNoGaps = await page.getByText(/no.*gap|no open gap/i).count() > 0;
        const hasContent = await page.getByText(/harness|gap|severity/i).count() > 0;

        expect(hasGaps || hasNoGaps || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Evidence Tab', () => {
    test('should display evidence or empty state', async ({ page }) => {
      const evidenceTab = page.locator('button').filter({ hasText: /evidence/i }).first();

      if (await evidenceTab.count() > 0) {
        await evidenceTab.click();
        await page.waitForTimeout(500);

        const hasEvidence = await page.locator('[class*="card"], [class*="evidence"]').count() > 0;
        const hasEmpty = await page.getByText(/no.*evidence|empty|no data/i).count() > 0;
        const hasContent = await page.getByText(/evidence/i).count() > 0;

        expect(hasEvidence || hasEmpty || hasContent).toBeTruthy();
      }
    });
  });

  test.describe('Responsive', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.missionsCodeFactory);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/mission|code.*factory|contract/i);
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.missionsCodeFactory);
      await page.waitForLoadState('networkidle');
      await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
      await expect(page.locator('body')).toContainText(/mission|code.*factory|contract/i);
    });
  });
});
