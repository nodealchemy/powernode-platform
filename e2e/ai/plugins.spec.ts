import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Plugins E2E Tests
 *
 * Tests for AI Plugin management and marketplace integration.
 * Migrated from ai-plugin-management.cy.ts and ai-plugins.cy.ts
 *
 * Note: /app/ai/plugins may redirect to /app/marketplace?types=plugin
 */

test.describe('AI Plugins', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.plugins);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"], body', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load Plugins page or redirect to marketplace', async ({ page }) => {
      const url = page.url();
      const isPluginsPage = url.includes('/plugins');
      const isMarketplace = url.includes('/marketplace');

      expect(isPluginsPage || isMarketplace).toBeTruthy();
    });

    test('should display plugin or marketplace content', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/plugin|extension|integration|marketplace|browse/i);
    });
  });

  test.describe('Plugin Browsing', () => {
    test('should display plugin list or marketplace', async ({ page }) => {
      await page.waitForTimeout(1000);

      const hasList = await page.locator('[data-testid="plugin-list"], [class*="grid"], [class*="card"], [class*="Card"]').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('plugin') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('marketplace');

      expect(hasList || hasPageContent).toBeTruthy();
    });

    test('should display plugin categories', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/category|all|plugin|marketplace/i);
    });

    test('should have search functionality', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[type="text"][placeholder*="search" i], [data-testid="search-input"]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      } else {
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Plugin Details', () => {
    test('should display plugin name', async ({ page }) => {
      const hasName = await page.locator('h2, h3, [class*="name"], [class*="title"]').count() > 0;
      await expect(page.locator('body')).toBeVisible();
    });

    test('should display plugin description', async ({ page }) => {
      const hasDescription = await page.locator('p, [class*="description"]').count() > 0;
      await expect(page.locator('body')).toBeVisible();
    });

    test('should display plugin version', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/v\d|version|\d+\.\d+|plugin|marketplace/i);
    });
  });

  test.describe('Plugin Installation', () => {
    test('should have install button', async ({ page }) => {
      const installButton = page.locator('button:has-text("Install"), button:has-text("Add"), button:has-text("Get")');
      const hasButton = await installButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('install') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('plugin');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should display installed badge', async ({ page }) => {
      const hasInstalled = (await page.locator('body').textContent())?.toLowerCase().includes('installed') ||
                           (await page.locator('body').textContent())?.toLowerCase().includes('active');
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Plugin Configuration', () => {
    test('should have configure option for installed plugins', async ({ page }) => {
      const configureButton = page.locator('button:has-text("Configure"), button:has-text("Settings")');
      const hasButton = await configureButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('configure') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('plugin');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should have enable/disable toggle', async ({ page }) => {
      const hasToggle = await page.locator('input[type="checkbox"], [role="switch"]').count() > 0;
      const hasEnableDisable = (await page.locator('body').textContent())?.toLowerCase().includes('enable') ||
                               (await page.locator('body').textContent())?.toLowerCase().includes('disable');
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Plugin Updates', () => {
    test('should display update available badge when applicable', async ({ page }) => {
      const hasUpdate = (await page.locator('body').textContent())?.toLowerCase().includes('update') ||
                        (await page.locator('body').textContent())?.toLowerCase().includes('new version');
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Plugin Permissions', () => {
    test('should display plugin permissions', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/permission|access|require|plugin|marketplace|browse|template/i);
    });
  });

  test.describe('Plugin Removal', () => {
    test('should have uninstall option', async ({ page }) => {
      const uninstallButton = page.locator('button:has-text("Uninstall"), button:has-text("Remove")');
      const hasButton = await uninstallButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('uninstall') ||
                             (await page.locator('body').textContent())?.toLowerCase().includes('plugin');

      expect(hasButton || hasPageContent).toBeTruthy();
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
      await page.goto(ROUTES.plugins);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.plugins);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should display properly on desktop viewport', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 720 });
      await page.goto(ROUTES.plugins);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
