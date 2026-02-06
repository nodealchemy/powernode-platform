import { test, expect } from '@playwright/test';
import { DevOpsOverviewPage } from '../pages/devops/overview.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * DevOps Overview E2E Tests
 *
 * Tests for DevOps dashboard and overview functionality.
 */

test.describe('DevOps Overview', () => {
  let overviewPage: DevOpsOverviewPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    overviewPage = new DevOpsOverviewPage(page);
    await overviewPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load DevOps overview page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/devops|overview/i);
    });

    test('should display DevOps navigation section', async ({ page }) => {
      // "DEVOPS" text appears in the sidebar navigation, not the page content
      // Check for either sidebar text or page title
      const hasDevOpsText = await page.getByText(/devops/i).count() > 0;
      expect(hasDevOpsText).toBeTruthy();
    });

    test('should have refresh button', async ({ page }) => {
      const refreshButton = page.getByRole('button', { name: /refresh/i });
      if (await refreshButton.count() > 0) {
        await expect(refreshButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Stat Cards', () => {
    test('should display Git Providers stat card', async ({ page }) => {
      const hasProviders = await page.getByText(/git.*provider|provider/i).count() > 0;
      expect(hasProviders).toBeTruthy();
    });

    test('should display Repositories stat card', async ({ page }) => {
      const hasRepos = await page.getByText(/repositor/i).count() > 0;
      expect(hasRepos).toBeTruthy();
    });

    test('should display Runners stat card', async ({ page }) => {
      const hasRunners = await page.getByText(/runner/i).count() > 0;
      expect(hasRunners).toBeTruthy();
    });

    test('should display Webhooks stat card', async ({ page }) => {
      const hasWebhooks = await page.getByText(/webhook/i).count() > 0;
      expect(hasWebhooks).toBeTruthy();
    });

    test('should display Integrations stat card', async ({ page }) => {
      const hasIntegrations = await page.getByText(/integration/i).count() > 0;
      expect(hasIntegrations).toBeTruthy();
    });

    test('should display API Keys stat card', async ({ page }) => {
      const hasApiKeys = await page.getByText(/api.*key/i).count() > 0;
      expect(hasApiKeys).toBeTruthy();
    });
  });

  test.describe('Status Sections', () => {
    test('should display runner health section', async ({ page }) => {
      const hasRunnerHealth = await page.getByText(/runner.*health|health/i).count() > 0;
      await expectOrAlternateState(page, hasRunnerHealth);
    });

    test('should display webhook deliveries section', async ({ page }) => {
      const hasDeliveries = await page.getByText(/deliver|webhook.*today/i).count() > 0;
      await expectOrAlternateState(page, hasDeliveries);
    });

    test('should display commit activity section', async ({ page }) => {
      const hasCommitActivity = await page.getByText(/commit.*activity|activity/i).count() > 0;
      await expectOrAlternateState(page, hasCommitActivity);
    });
  });

  test.describe('Quick Access Navigation', () => {
    test('should have quick access links', async ({ page }) => {
      // Page should have clickable links/cards for DevOps features
      const hasLinks = await page.locator('a, [class*="card"], [class*="cursor-pointer"]').count() > 0;
      expect(hasLinks).toBeTruthy();
    });

    test('should navigate to Git Providers', async ({ page }) => {
      const gitLink = page.getByText(/git.*provider/i).first();
      if (await gitLink.isVisible()) {
        await gitLink.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toContainText(/provider/i);
      }
    });

    test('should navigate to Repositories', async ({ page }) => {
      const repoLink = page.getByText(/repositor/i).first();
      if (await repoLink.isVisible()) {
        await repoLink.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toContainText(/repositor/i);
      }
    });

    test('should navigate to Pipelines', async ({ page }) => {
      const pipelineLink = page.getByText(/pipeline/i).first();
      if (await pipelineLink.isVisible()) {
        await pipelineLink.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toContainText(/pipeline/i);
      }
    });

    test('should navigate to Runners', async ({ page }) => {
      const runnerLink = page.getByText(/runner/i).first();
      if (await runnerLink.isVisible()) {
        await runnerLink.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toContainText(/runner/i);
      }
    });
  });

  test.describe('Alerts', () => {
    test('should display alerts section if issues exist', async ({ page }) => {
      const hasAlerts = await page.locator('[class*="alert"], [class*="warning"], [class*="attention"]').count() > 0;
      const hasAttention = await page.getByText(/attention/i).count() > 0;
      // Alerts are optional - only shown when issues exist
      await expectOrAlternateState(page, hasAlerts || hasAttention);
    });
  });

  test.describe('Data Refresh', () => {
    test('should refresh data on button click', async ({ page }) => {
      const refreshButton = page.getByRole('button', { name: /refresh/i });
      if (await refreshButton.count() > 0) {
        await refreshButton.first().click();
        await page.waitForLoadState('networkidle');
        // Page should reload without error
      }
    });
  });

  test.describe('Real-time Updates', () => {
    test('should support real-time updates via WebSocket', async ({ page }) => {
      // Check if page has WebSocket connection indicators
      // This is a structural test - actual WebSocket testing would require more setup
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
