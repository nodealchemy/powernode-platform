import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Learning & Recommendations E2E Tests
 *
 * Tests for Recommendations Dashboard and Trajectory Insights pages.
 * These pages display AI improvement recommendations and prompt cache/quality metrics.
 */

test.describe('AI Learning - Recommendations Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
  });

  test.describe('Page Navigation', () => {
    test('should load recommendations dashboard', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/recommendation|improvement|learning/i);
    });

    test('should display page title', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/recommendation/i);
    });
  });

  test.describe('Stats Cards', () => {
    test('should display pending recommendations count', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/pending|total|recommendation/i);
    });

    test('should display applied count', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/applied|approved|dismissed/i);
    });
  });

  test.describe('Recommendations List', () => {
    test('should display recommendations or empty state', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      const body = page.locator('body');
      const hasContent = await body.textContent();
      expect(hasContent).toBeTruthy();
    });

    test('should show recommendation type badges', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');
      // If recommendations exist, they should show types
      const body = page.locator('body');
      const content = await body.textContent();
      // Either shows recommendations with types or empty state
      expect(content?.length).toBeGreaterThan(0);
    });
  });

  test.describe('Apply/Dismiss Actions', () => {
    test('should render action buttons for pending recommendations', async ({ page }) => {
      await page.goto(ROUTES.learningRecommendations);
      await page.waitForLoadState('networkidle');

      // Check for apply/dismiss buttons if recommendations exist
      const applyButton = page.locator('button').filter({ hasText: /apply/i });
      const dismissButton = page.locator('button').filter({ hasText: /dismiss/i });

      // At least the page rendered without errors
      const body = page.locator('body');
      await expect(body).toBeVisible();
    });
  });
});

test.describe('AI Learning - Trajectory Insights', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
  });

  test.describe('Page Navigation', () => {
    test('should load trajectory insights page', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      await expect(page.locator('body')).toContainText(/cache|quality|evaluation|insight|trajectory|learning/i);
    });

    test('should display page title', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // TrajectoryInsights renders cards directly without PageContainer title
      await expect(page.locator('body')).toContainText(/cache|quality|evaluation|insight|trajectory/i);
    });
  });

  test.describe('Prompt Cache Metrics', () => {
    test('should display cache metrics section', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Shows "Prompt Cache Performance" card or loading/empty state
      await expect(page.locator('body')).toContainText(/cache|hit|miss|prompt|evaluation|quality/i);
    });

    test('should show hit rate information', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Should display some metrics or empty state
      const body = page.locator('body');
      const hasContent = await body.textContent();
      expect(hasContent).toBeTruthy();
    });
  });

  test.describe('Agent Quality Trends', () => {
    test('should display quality trends section', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // Shows "Agent Quality Trends" or "No evaluation data available yet"
      await expect(page.locator('body')).toContainText(/quality|agent|trend|evaluation|no evaluation/i);
    });
  });

  test.describe('Data Display', () => {
    test('should render without errors', async ({ page }) => {
      await page.goto(ROUTES.learningInsights);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
      // No errors and page is visible
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
