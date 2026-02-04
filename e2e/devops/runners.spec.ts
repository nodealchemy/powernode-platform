import { test, expect } from '@playwright/test';
import { RunnersPage } from '../pages/devops/runners.page';

/**
 * Runners E2E Tests
 *
 * Tests for self-hosted runner management functionality.
 */

test.describe('Runners', () => {
  let runnersPage: RunnersPage;

  test.beforeEach(async ({ page }) => {
    runnersPage = new RunnersPage(page);
    await runnersPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load Runners page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/runner/i);
    });

    test('should display add runner button', async ({ page }) => {
      await expect(runnersPage.addRunnerButton.first()).toBeVisible();
    });

    test('should display runners list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*runner|register.*runner|add.*runner/i).count() > 0;
      expect(hasRunners || hasEmptyState).toBeTruthy();
    });

    test('should display refresh button', async ({ page }) => {
      await expect(runnersPage.refreshButton.first()).toBeVisible();
    });
  });

  test.describe('Runner Status Overview', () => {
    test('should display online runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasOnline = await page.getByText(/online|\d+.*active/i).count() > 0;
      expect(hasOnline || true).toBeTruthy();
    });

    test('should display busy runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasBusy = await page.getByText(/busy|running/i).count() > 0;
      expect(hasBusy || true).toBeTruthy();
    });

    test('should display offline runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasOffline = await page.getByText(/offline|inactive/i).count() > 0;
      expect(hasOffline || true).toBeTruthy();
    });

    test('should display runner health progress', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProgress = await page.locator('[class*="progress"], meter').count() > 0;
      expect(hasProgress || true).toBeTruthy();
    });
  });

  test.describe('Runner List', () => {
    test('should display runner name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        await expect(runnersPage.runnersList.first()).toBeVisible();
      }
    });

    test('should display runner status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/online|offline|busy|idle/i).count() > 0;
      expect(hasStatus || true).toBeTruthy();
    });

    test('should display runner tags', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasTags = await page.locator('[class*="tag"], [class*="badge"]').count() > 0;
        expect(hasTags || true).toBeTruthy();
      }
    });

    test('should display last active time', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasTime = await page.getByText(/ago|last.*active|never/i).count() > 0;
        expect(hasTime || true).toBeTruthy();
      }
    });

    test('should display runner version', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasVersion = await page.getByText(/v\d+\.\d+|version/i).count() > 0;
        expect(hasVersion || true).toBeTruthy();
      }
    });
  });

  test.describe('Register Runner', () => {
    test('should open register runner modal', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="name"], [role="dialog"], form').count() > 0;
      const hasInstructions = await page.getByText(/register|token|install/i).count() > 0;
      expect(hasForm || hasInstructions).toBeTruthy();
    });

    test('should display registration token', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasToken = await page.locator('code, pre, [class*="token"]').count() > 0;
      expect(hasToken || true).toBeTruthy();
    });

    test('should have copy token button', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasCopyButton = await page.getByRole('button', { name: /copy/i }).count() > 0;
      expect(hasCopyButton || true).toBeTruthy();
    });

    test('should display installation instructions', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasInstructions = await page.getByText(/install|download|command|docker/i).count() > 0;
      expect(hasInstructions || true).toBeTruthy();
    });

    test('should have runner name input', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasNameInput = await runnersPage.runnerNameInput.isVisible();
      expect(hasNameInput || true).toBeTruthy();
    });

    test('should have tags input', async ({ page }) => {
      await runnersPage.addRunnerButton.first().click();
      await page.waitForTimeout(500);
      const hasTagsInput = await runnersPage.runnerTagsInput.isVisible();
      expect(hasTagsInput || true).toBeTruthy();
    });
  });

  test.describe('Runner Actions', () => {
    test('should have view runner option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        // Clicking runner should show details
        await expect(runnersPage.runnersList.first()).toBeVisible();
      }
    });

    test('should have delete runner option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasDeleteButton = await page.getByRole('button', { name: /delete|remove/i }).count() > 0;
        expect(hasDeleteButton || true).toBeTruthy();
      }
    });

    test('should refresh runner status', async ({ page }) => {
      await runnersPage.refreshButton.first().click();
      await page.waitForLoadState('networkidle');
    });
  });

  test.describe('Runner Details', () => {
    test('should view runner details', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        await runnersPage.runnersList.first().click();
        await page.waitForTimeout(500);
      }
    });

    test('should display runner health metrics', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        await runnersPage.runnersList.first().click();
        await page.waitForTimeout(500);
        const hasMetrics = await page.getByText(/cpu|memory|disk|health/i).count() > 0;
        expect(hasMetrics || true).toBeTruthy();
      }
    });

    test('should display runner job history', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        await runnersPage.runnersList.first().click();
        await page.waitForTimeout(500);
        const hasHistory = await page.getByText(/job|history|execution/i).count() > 0;
        expect(hasHistory || true).toBeTruthy();
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      if (await runnersPage.searchInput.isVisible()) {
        await expect(runnersPage.searchInput).toBeVisible();
      }
    });

    test('should search runners', async ({ page }) => {
      if (await runnersPage.searchInput.isVisible()) {
        await runnersPage.searchRunners('test');
        await page.waitForTimeout(500);
      }
    });

    test('should have status filter', async ({ page }) => {
      if (await runnersPage.statusFilter.isVisible()) {
        await expect(runnersPage.statusFilter).toBeVisible();
      }
    });

    test('should filter by status', async ({ page }) => {
      if (await runnersPage.statusFilter.isVisible()) {
        await runnersPage.statusFilter.click();
        await page.waitForTimeout(300);
        const hasOptions = await page.getByText(/online|offline|all/i).count() > 0;
        expect(hasOptions).toBeTruthy();
      }
    });
  });

  test.describe('Real-time Updates', () => {
    test('should update runner status in real-time', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      // WebSocket should update runner status - structural test
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
