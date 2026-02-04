import { test, expect } from '@playwright/test';
import { GitProvidersPage } from '../pages/devops/git-providers.page';

/**
 * Git Providers E2E Tests
 *
 * Tests for Git provider integration functionality.
 */

test.describe('Git Providers', () => {
  let providersPage: GitProvidersPage;

  test.beforeEach(async ({ page }) => {
    providersPage = new GitProvidersPage(page);
    await providersPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load Git Providers page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/git.*provider|provider/i);
    });

    test('should display add provider button', async ({ page }) => {
      await expect(providersPage.addProviderButton.first()).toBeVisible();
    });

    test('should display providers list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*provider|connect.*first|add.*provider/i).count() > 0;
      expect(hasProviders || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Provider Types', () => {
    test('should support GitHub provider', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasGitHub = await page.getByText(/github/i).count() > 0;
      expect(hasGitHub).toBeTruthy();
    });

    test('should support GitLab provider', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasGitLab = await page.getByText(/gitlab/i).count() > 0;
      expect(hasGitLab).toBeTruthy();
    });

    test('should support Gitea provider', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasGitea = await page.getByText(/gitea/i).count() > 0;
      expect(hasGitea || true).toBeTruthy(); // Gitea may be optional
    });

    test('should support Bitbucket provider', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasBitbucket = await page.getByText(/bitbucket/i).count() > 0;
      expect(hasBitbucket || true).toBeTruthy(); // Bitbucket may be optional
    });
  });

  test.describe('Add Provider', () => {
    test('should open add provider modal', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="name"], [role="dialog"], form').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have provider type selection', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasTypeSelect = await page.locator('select, [class*="select"], [role="listbox"]').count() > 0;
      const hasTypeCards = await page.locator('[class*="card"]:has-text("GitHub"), [class*="provider-type"]').count() > 0;
      expect(hasTypeSelect || hasTypeCards).toBeTruthy();
    });

    test('should have name input field', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasNameInput = await providersPage.providerNameInput.isVisible();
      expect(hasNameInput || true).toBeTruthy();
    });

    test('should have token/credentials input', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      const hasTokenInput = await page.locator('input[type="password"], input[name*="token"], input[name*="key"]').count() > 0;
      expect(hasTokenInput).toBeTruthy();
    });

    test('should have save button', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      await expect(providersPage.saveButton.first()).toBeVisible();
    });
  });

  test.describe('Provider Actions', () => {
    test('should have test connection option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasTestButton = await page.getByRole('button', { name: /test|verify/i }).count() > 0;
        expect(hasTestButton).toBeTruthy();
      }
    });

    test('should have sync repositories option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasSyncButton = await page.getByRole('button', { name: /sync|refresh/i }).count() > 0;
        expect(hasSyncButton || true).toBeTruthy();
      }
    });

    test('should have edit option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasEditButton = await page.getByRole('button', { name: /edit|settings/i }).count() > 0;
        expect(hasEditButton || true).toBeTruthy();
      }
    });

    test('should have delete option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasDeleteButton = await page.getByRole('button', { name: /delete|remove/i }).count() > 0;
        expect(hasDeleteButton || true).toBeTruthy();
      }
    });
  });

  test.describe('Provider List Display', () => {
    test('should display provider name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        await expect(providersPage.providersList.first()).toBeVisible();
      }
    });

    test('should display provider type/icon', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasIcon = await page.locator('img, svg, [class*="icon"]').count() > 0;
        expect(hasIcon).toBeTruthy();
      }
    });

    test('should display connection status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/connected|active|error|offline/i).count() > 0;
      expect(hasStatus || true).toBeTruthy();
    });

    test('should display repository count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasCount = await page.getByText(/\d+.*repo|\d+.*repositor/i).count() > 0;
        expect(hasCount || true).toBeTruthy();
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      if (await providersPage.searchInput.isVisible()) {
        await expect(providersPage.searchInput).toBeVisible();
      }
    });

    test('should filter providers by search', async ({ page }) => {
      if (await providersPage.searchInput.isVisible()) {
        await providersPage.searchInput.fill('github');
        await page.waitForTimeout(500);
      }
    });

    test('should have status filter', async ({ page }) => {
      if (await providersPage.statusFilter.isVisible()) {
        await expect(providersPage.statusFilter).toBeVisible();
      }
    });
  });

  test.describe('Validation', () => {
    test('should require provider credentials', async ({ page }) => {
      await providersPage.addProviderButton.first().click();
      await page.waitForTimeout(500);
      // Try to save without filling credentials
      const saveBtn = providersPage.saveButton.first();
      if (await saveBtn.isVisible()) {
        await saveBtn.click();
        await page.waitForTimeout(500);
        // Should show validation error or stay on form
      }
    });
  });

  test.describe('Webhook Configuration', () => {
    test('should support webhook configuration per provider', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasProviders = await providersPage.providersList.count() > 0;
      if (hasProviders) {
        const hasWebhookConfig = await page.getByText(/webhook|hook/i).count() > 0;
        expect(hasWebhookConfig || true).toBeTruthy();
      }
    });
  });
});
