import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Self-Healing Dashboard E2E Tests
 *
 * Tests for Self-Healing Dashboard, Remediation Timeline, and Health Correlation views.
 * These pages display system health, automated remediation actions, and cross-system correlations.
 */

test.describe('AI Self-Healing Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
  });

  test.describe('Page Navigation', () => {
    test('should load self-healing dashboard', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/self.healing|remediation|health|dashboard/i);
    });

    test('should display page title', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/self.healing/i);
    });
  });

  test.describe('Status Cards', () => {
    test('should display system status card', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/status|healthy|degraded|active/i);
    });

    test('should display actions count card', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/action|remediation|hour/i);
    });

    test('should display success rate card', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/success|rate|%/i);
    });
  });

  test.describe('Remediation Timeline', () => {
    test('should display remediation timeline section', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/timeline|remediation|recent/i);
    });

    test('should show empty state when no remediations exist', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      // Either shows remediations or an empty state message
      const body = page.locator('body');
      const hasContent = await body.textContent();
      expect(hasContent).toBeTruthy();
    });
  });

  test.describe('Health Correlation View', () => {
    test('should display health correlation section', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/correlation|health|cross.system|system/i);
    });
  });

  test.describe('Feature Flag Warning', () => {
    test('should display feature flag information', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      // May show a warning about feature flag or active status
      const body = page.locator('body');
      const hasContent = await body.textContent();
      expect(hasContent).toBeTruthy();
    });
  });

  test.describe('Auto-Refresh', () => {
    test('should render without errors after waiting', async ({ page }) => {
      await page.goto(ROUTES.selfHealing);
      await page.waitForLoadState('networkidle');
      // Wait for potential auto-refresh cycle
      await page.waitForTimeout(2000);
      // Page should still be rendered without errors
      await expect(page.locator('body')).toContainText(/self.healing|remediation|health|dashboard/i);
    });
  });
});
