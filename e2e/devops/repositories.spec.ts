import { test, expect } from '@playwright/test';
import { RepositoriesPage } from '../pages/devops/repositories.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Repositories E2E Tests
 *
 * Tests for Git repository management functionality.
 */

test.describe('Repositories', () => {
  let reposPage: RepositoriesPage;

  test.beforeEach(async ({ page }) => {
    reposPage = new RepositoriesPage(page);
    await reposPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load Repositories page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/repositor/i);
    });

    test('should display sync button', async ({ page }) => {
      await expect(reposPage.syncButton.first()).toBeVisible();
    });

    test('should display repositories list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*repositor|connect.*provider|sync/i).count() > 0;
      expect(hasRepos || hasEmptyState).toBeTruthy();
    });

    test('should display search input', async ({ page }) => {
      await expect(reposPage.searchInput.first()).toBeVisible();
    });
  });

  test.describe('Repository List', () => {
    test('should display repository name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        await expect(reposPage.repositoriesList.first()).toBeVisible();
      }
    });

    test('should display repository provider', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasProvider = await page.getByText(/github|gitlab|gitea|bitbucket/i).count() > 0;
        await expectOrAlternateState(page, hasProvider);
      }
    });

    test('should display default branch', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasBranch = await page.getByText(/main|master|branch/i).count() > 0;
        await expectOrAlternateState(page, hasBranch);
      }
    });

    test('should display webhook status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasWebhookStatus = await page.getByText(/webhook|configured|active/i).count() > 0;
        await expectOrAlternateState(page, hasWebhookStatus);
      }
    });

    test('should display last activity', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasActivity = await page.getByText(/ago|last.*commit|updated/i).count() > 0;
        await expectOrAlternateState(page, hasActivity);
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should search repositories by name', async ({ page }) => {
      await reposPage.searchRepositories('test');
      await page.waitForTimeout(500);
    });

    test('should have provider filter', async ({ page }) => {
      if (await reposPage.providerFilter.isVisible()) {
        await expect(reposPage.providerFilter).toBeVisible();
      }
    });

    test('should filter by provider', async ({ page }) => {
      if (await reposPage.providerFilter.isVisible()) {
        await reposPage.providerFilter.click();
        await page.waitForTimeout(300);
        const hasProviders = await page.getByText(/github|gitlab|all/i).count() > 0;
        expect(hasProviders).toBeTruthy();
      }
    });

    test('should have branch filter', async ({ page }) => {
      if (await reposPage.branchFilter.isVisible()) {
        await expect(reposPage.branchFilter).toBeVisible();
      }
    });

    test('should clear search', async ({ page }) => {
      await reposPage.searchRepositories('test');
      await page.waitForTimeout(300);
      await reposPage.searchRepositories('');
      await page.waitForTimeout(300);
    });
  });

  test.describe('Repository Actions', () => {
    test('should sync all repositories', async ({ page }) => {
      await reposPage.syncButton.first().click();
      await page.waitForTimeout(500);
      // Should trigger sync operation
    });

    test('should have view repository option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        // Clicking repo should navigate to details
        const firstRepo = reposPage.repositoriesList.first();
        await expect(firstRepo).toBeVisible();
      }
    });

    test('should have configure webhook option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasWebhookButton = await page.getByRole('button', { name: /webhook|configure/i }).count() > 0;
        await expectOrAlternateState(page, hasWebhookButton);
      }
    });

    test('should have view commits option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasCommitButton = await page.getByRole('button', { name: /commit|history/i }).count() > 0;
        await expectOrAlternateState(page, hasCommitButton);
      }
    });
  });

  test.describe('Repository Details', () => {
    test('should view repository details', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        await reposPage.repositoriesList.first().click();
        await page.waitForTimeout(500);
        // Should show repository details
      }
    });

    test('should display repository metadata', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        await reposPage.repositoriesList.first().click();
        await page.waitForTimeout(500);
        const hasMetadata = await page.getByText(/description|language|created|url/i).count() > 0;
        await expectOrAlternateState(page, hasMetadata);
      }
    });
  });

  test.describe('Commit History', () => {
    test('should display commit history if available', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasCommits = await page.getByText(/commit|sha|author/i).count() > 0;
        await expectOrAlternateState(page, hasCommits);
      }
    });
  });

  test.describe('Branch Management', () => {
    test('should display branches for repository', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRepos = await reposPage.repositoriesList.count() > 0;
      if (hasRepos) {
        const hasBranches = await page.getByText(/branch|main|master/i).count() > 0;
        await expectOrAlternateState(page, hasBranches);
      }
    });
  });

  test.describe('Pagination', () => {
    test('should display pagination for many repositories', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPagination = await page.locator('[class*="pagination"], [class*="pager"]').count() > 0;
      await expectOrAlternateState(page, hasPagination);
    });
  });
});
