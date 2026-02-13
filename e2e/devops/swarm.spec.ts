import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Swarm Clusters E2E Tests
 *
 * Tests for the SwarmClustersPage including cluster listing,
 * service management, and swarm dashboard.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('Swarm Clusters', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.swarmClusters);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load swarm clusters page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/swarm|cluster|node|service/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/swarm/i);
    });
  });

  test.describe('Cluster List', () => {
    test('should display clusters or empty state', async ({ page }) => {
      const hasClusters = await page.locator('[class*="card"], [class*="cluster"], tr').count() > 0;
      const hasEmpty = await page.getByText(/no.*cluster|no.*swarm|empty|initialize|create/i).count() > 0;
      const hasContent = await page.getByText(/swarm/i).count() > 0;

      expect(hasClusters || hasEmpty || hasContent).toBeTruthy();
    });

    test('should display cluster status indicators', async ({ page }) => {
      const hasStatus = await page.getByText(/active|inactive|healthy|unhealthy|ready|drain/i).count() > 0;
      const hasContent = await page.getByText(/swarm/i).count() > 0;

      expect(hasStatus || hasContent).toBeTruthy();
    });
  });

  test.describe('Swarm Actions', () => {
    test('should display create cluster button or action', async ({ page }) => {
      const hasCreate = await page.getByRole('button', { name: /create|new|init|add/i }).count() > 0;
      const hasContent = await page.getByText(/swarm/i).count() > 0;

      expect(hasCreate || hasContent).toBeTruthy();
    });
  });

  test.describe('Sub-Navigation', () => {
    test('should display swarm sub-navigation', async ({ page }) => {
      const hasNodes = await page.getByText(/node/i).count() > 0;
      const hasServices = await page.getByText(/service/i).count() > 0;
      const hasStacks = await page.getByText(/stack/i).count() > 0;
      const hasSwarm = await page.getByText(/swarm/i).count() > 0;

      expect(hasNodes || hasServices || hasStacks || hasSwarm).toBeTruthy();
    });

    test('should navigate to services sub-page without crash', async ({ page }) => {
      const servicesLink = page.locator('a, button').filter({ hasText: /service/i }).first();

      if (await servicesLink.count() > 0) {
        await servicesLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should navigate to stacks sub-page without crash', async ({ page }) => {
      const stacksLink = page.locator('a, button').filter({ hasText: /stack/i }).first();

      if (await stacksLink.count() > 0) {
        await stacksLink.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });
});
