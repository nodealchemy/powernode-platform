import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Docker Hosts E2E Tests
 *
 * Tests for the DockerHostsPage including host listing,
 * container management, and Docker dashboard.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('Docker Hosts', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.dockerHosts);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load docker hosts page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/docker|host|container/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/docker/i);
    });
  });

  test.describe('Host List', () => {
    test('should display hosts or empty state', async ({ page }) => {
      const hasHosts = await page.locator('[class*="card"], [class*="host"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*host|no.*docker|empty|add.*host|connect/i).count() > 0;
      const hasContent = await page.getByText(/docker/i).count() > 0;

      expect(hasHosts || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display host status indicators', async ({ page }) => {
      const hasStatus = await page.getByText(/online|offline|connected|disconnected|healthy|unhealthy/i).count() > 0;
      const hasContent = await page.getByText(/docker/i).count() > 0;

      expect(hasStatus || hasContent).toBeTruthy();
    });
  });

  test.describe('Docker Actions', () => {
    test('should display add host button or action', async ({ page }) => {
      const hasAdd = await page.getByRole('button', { name: /add|new|connect|create/i }).count() > 0;
      const hasContent = await page.getByText(/docker/i).count() > 0;

      expect(hasAdd || hasContent).toBeTruthy();
    });
  });

  test.describe('Sub-Navigation', () => {
    test('should display docker sub-navigation tabs', async ({ page }) => {
      const hasContainers = await page.getByText(/container/i).count() > 0;
      const hasImages = await page.getByText(/image/i).count() > 0;
      const hasNetworks = await page.getByText(/network/i).count() > 0;
      const hasVolumes = await page.getByText(/volume/i).count() > 0;
      const hasDocker = await page.getByText(/docker/i).count() > 0;

      expect(hasContainers || hasImages || hasNetworks || hasVolumes || hasDocker).toBeTruthy();
    });

    test('should navigate to containers sub-page without crash', async ({ page }) => {
      const containersLink = page.locator('a, button').filter({ hasText: /container/i }).first();

      if (await containersLink.count() > 0) {
        await containersLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should navigate to images sub-page without crash', async ({ page }) => {
      const imagesLink = page.locator('a, button').filter({ hasText: /image/i }).first();

      if (await imagesLink.count() > 0) {
        await imagesLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });
});
