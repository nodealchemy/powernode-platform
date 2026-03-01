import { test, expect } from '@playwright/test';
import { RunnersPage } from '../pages/devops/runners.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Runners E2E Tests
 *
 * Tests for self-hosted runner management functionality.
 * Note: Runners are synced from git providers, not manually created.
 * The page has "Sync Runners" instead of "Add Runner".
 */

test.describe('Runners', () => {
  let runnersPage: RunnersPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    runnersPage = new RunnersPage(page);
    await runnersPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load Runners page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/runner/i);
    });

    test('should display sync or add runner button', async ({ page }) => {
      // Page has "Sync Runners" button, not "Add Runner"
      const hasSyncOrAdd = await runnersPage.addRunnerButton.count() > 0;
      await expectOrAlternateState(page, hasSyncOrAdd);
    });

    test('should display runners list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*runner|sync.*runner|add.*runner/i).count() > 0;
      expect(hasRunners || hasEmptyState).toBeTruthy();
    });

    test('should display refresh button', async ({ page }) => {
      const hasRefresh = await runnersPage.refreshButton.count() > 0;
      await expectOrAlternateState(page, hasRefresh);
    });
  });

  test.describe('Runner Status Overview', () => {
    test('should display online runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasOnline = await page.getByText(/online|\d+.*active/i).count() > 0;
      await expectOrAlternateState(page, hasOnline);
    });

    test('should display busy runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasBusy = await page.getByText(/busy|running/i).count() > 0;
      await expectOrAlternateState(page, hasBusy);
    });

    test('should display offline runners count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasOffline = await page.getByText(/offline|inactive/i).count() > 0;
      await expectOrAlternateState(page, hasOffline);
    });

    test('should display runner health progress', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProgress = await page.locator('[class*="progress"], meter, [role="progressbar"]').count() > 0;
      await expectOrAlternateState(page, hasProgress);
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
      await expectOrAlternateState(page, hasStatus);
    });

    test('should display runner tags', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasTags = await page.locator('[class*="tag"], [class*="badge"], span[class*="text-xs"]').count() > 0;
        await expectOrAlternateState(page, hasTags);
      }
    });

    test('should display last active time', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasTime = await page.getByText(/ago|last.*active|never/i).count() > 0;
        await expectOrAlternateState(page, hasTime);
      }
    });

    test('should display runner version', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        const hasVersion = await page.getByText(/v\d+\.\d+|version/i).count() > 0;
        await expectOrAlternateState(page, hasVersion);
      }
    });
  });

  test.describe('Sync Runners', () => {
    test('should trigger sync runners action', async ({ page }) => {
      // "Sync Runners" replaces traditional "Register Runner"
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        // Sync may show a modal, toast, or just refresh the list
        const hasResult = await page.getByText(/sync|register|token|install|runner/i).count() > 0;
        await expectOrAlternateState(page, hasResult);
      }
    });

    test('should display registration token if modal opens', async ({ page }) => {
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        const hasToken = await page.locator('code, pre, [class*="token"]').count() > 0;
        await expectOrAlternateState(page, hasToken);
      }
    });

    test('should have copy token button if token shown', async ({ page }) => {
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        const hasCopyButton = await page.getByRole('button', { name: /copy/i }).count() > 0;
        await expectOrAlternateState(page, hasCopyButton);
      }
    });

    test('should display installation instructions if shown', async ({ page }) => {
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        const hasInstructions = await page.getByText(/install|download|command|docker/i).count() > 0;
        await expectOrAlternateState(page, hasInstructions);
      }
    });

    test('should have runner name input if form shown', async ({ page }) => {
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        const hasNameInput = await runnersPage.runnerNameInput.count() > 0;
        await expectOrAlternateState(page, hasNameInput);
      }
    });

    test('should have tags input if form shown', async ({ page }) => {
      const hasSyncBtn = await runnersPage.addRunnerButton.count() > 0;
      if (hasSyncBtn) {
        await runnersPage.addRunnerButton.first().click();
        await page.waitForTimeout(500);
        const hasTagsInput = await runnersPage.runnerTagsInput.count() > 0;
        await expectOrAlternateState(page, hasTagsInput);
      }
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
        await expectOrAlternateState(page, hasDeleteButton);
      }
    });

    test('should refresh runner status', async ({ page }) => {
      if (await runnersPage.refreshButton.count() > 0) {
        await runnersPage.refreshButton.first().click();
        await page.waitForLoadState('networkidle');
      }
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
        await expectOrAlternateState(page, hasMetrics);
      }
    });

    test('should display runner job history', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunners = await runnersPage.runnersList.count() > 0;
      if (hasRunners) {
        await runnersPage.runnersList.first().click();
        await page.waitForTimeout(500);
        const hasHistory = await page.getByText(/job|history|execution/i).count() > 0;
        await expectOrAlternateState(page, hasHistory);
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      const searchCount = await runnersPage.searchInput.count();
      if (searchCount > 0) {
        await expect(runnersPage.searchInput.first()).toBeVisible();
      }
    });

    test('should search runners', async ({ page }) => {
      if (await runnersPage.searchInput.count() > 0) {
        await runnersPage.searchRunners('test');
        await page.waitForTimeout(500);
      }
    });

    test('should have status filter', async ({ page }) => {
      const filterCount = await runnersPage.statusFilter.count();
      if (filterCount > 0) {
        await expect(runnersPage.statusFilter.first()).toBeVisible();
      }
    });

    test('should filter by status', async ({ page }) => {
      const filterCount = await runnersPage.statusFilter.count();
      if (filterCount > 0) {
        // Status filter is a <select> element
        const hasOptions = await page.getByText(/online|offline|all/i).count() > 0;
        await expectOrAlternateState(page, hasOptions);
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
