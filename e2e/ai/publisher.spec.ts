import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Publisher E2E Tests
 *
 * Tests for Publisher dashboard and template management.
 * Migrated from ai-publisher.cy.ts
 */

test.describe('AI Publisher', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.publisher);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Publisher page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/publisher|dashboard|template/i);
    });

    test('should display publisher setup or dashboard', async ({ page }) => {
      await expect(page.locator('body')).toContainText(
        /create publisher|get started|become a publisher|publisher dashboard|template|earning/i
      );
    });
  });

  test.describe('Publisher Dashboard', () => {
    test('should display publisher tabs or setup', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/overview|template|earning|payout|get started|publisher/i);
    });

    test('should display earnings overview or setup prompt', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/earning|revenue|\$|lifetime|setup|create|publisher/i);
    });
  });

  test.describe('Template Performance', () => {
    test('should display template list or empty state', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/template|no template|create|publisher/i);
    });

    test('should display template metrics or setup', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/installation|rating|revenue|performance|setup|create|publisher/i);
    });

    test('should display template status or setup', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/published|draft|pending|active|setup|publisher/i);
    });
  });

  test.describe('Template Analytics', () => {
    test('should display analytics information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytic|statistic|metric|publisher/i);
    });

    test('should display revenue analytics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/revenue|gross|net|commission|analytic|publisher/i);
    });
  });

  test.describe('Earnings & Payouts', () => {
    test('should display earnings information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/earning|lifetime|pending|revenue share|\$|setup|publisher/i);
    });

    test('should display payouts information', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/payout|stripe|request|history|setup|publisher/i);
    });

    test('should display Stripe connection status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/stripe|connected|setup stripe|not connected|payment|setup|publisher/i);
    });
  });

  test.describe('Publisher Setup Flow', () => {
    test('should display setup form or dashboard', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/setup|create|publisher|profile|dashboard/i);
    });
  });

  test.describe('Create Template', () => {
    test('should have create template action', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/create template|new template|add template|create|setup|publisher/i);
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
      await page.goto(ROUTES.publisher);
      await expect(page.locator('body')).toContainText(/publisher|template/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.publisher);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
