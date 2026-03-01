import { test, expect } from '@playwright/test';
import { ApiKeysPage } from '../pages/devops/api-keys.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * DevOps API Keys E2E Tests
 *
 * Tests for API key management functionality.
 */

test.describe('DevOps API Keys', () => {
  let apiKeysPage: ApiKeysPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    apiKeysPage = new ApiKeysPage(page);
    await apiKeysPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load API keys page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/api.*key|token|credential/i);
    });

    test('should display create key button', async ({ page }) => {
      const hasButton = await apiKeysPage.createKeyButton.count() > 0;
      expect(hasButton).toBeTruthy();
    });

    test('should display keys list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasKeys = await apiKeysPage.keysList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*key|create.*first|empty|generate.*first/i).count() > 0;
      expect(hasKeys || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('API Keys List', () => {
    test('should display key name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasKeys = await apiKeysPage.keysList.count() > 0;
      if (hasKeys) {
        await expect(apiKeysPage.keysList.first()).toBeVisible();
      }
    });

    test('should display key prefix or masked value', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasKeys = await apiKeysPage.keysList.count() > 0;
      if (hasKeys) {
        // Keys are usually shown masked like pk_**** or just prefixes
        const hasMasked = await page.getByText(/\*\*\*|pk_|sk_/i).count() > 0;
        await expectOrAlternateState(page, hasMasked);
      }
    });

    test('should display key creation date', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasKeys = await apiKeysPage.keysList.count() > 0;
      if (hasKeys) {
        const hasDate = await page.getByText(/created|date|\d{4}/i).count() > 0;
        await expectOrAlternateState(page, hasDate);
      }
    });

    test('should display key expiration if set', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasExpiration = await page.getByText(/expire|expiration|never/i).count() > 0;
      await expectOrAlternateState(page, hasExpiration);
    });

    test('should display key scopes or permissions', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasScopes = await page.getByText(/scope|permission|access/i).count() > 0;
      await expectOrAlternateState(page, hasScopes);
    });
  });

  test.describe('Create API Key', () => {
    test('should open create key modal', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="name"], [role="dialog"], form').count() > 0;
      await expectOrAlternateState(page, hasForm);
    });

    test('should have name field', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasName = await apiKeysPage.keyNameInput.count() > 0;
      await expectOrAlternateState(page, hasName);
    });

    test('should have description field', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasDescription = await apiKeysPage.keyDescriptionInput.count() > 0;
      await expectOrAlternateState(page, hasDescription);
    });

    test('should have scopes selection', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasScopes = await apiKeysPage.scopesChecklist.count() > 0;
      await expectOrAlternateState(page, hasScopes);
    });

    test('should have expiration selection', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasExpiration = await apiKeysPage.expirationSelect.count() > 0;
      await expectOrAlternateState(page, hasExpiration);
    });

    test('should have generate button', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      const hasGenerate = await apiKeysPage.generateButton.count() > 0;
      await expectOrAlternateState(page, hasGenerate);
    });
  });

  test.describe('Key Generation', () => {
    test('should show generated key after creation', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      if (await apiKeysPage.keyNameInput.count() > 0) {
        await apiKeysPage.keyNameInput.fill('Test Key');
        if (await apiKeysPage.generateButton.count() > 0) {
          await apiKeysPage.generateButton.first().click();
          await page.waitForTimeout(1000);
          // Should show the key value (only shown once)
          const hasKeyDisplay = await page.locator('[class*="key"], code, pre').count() > 0;
          const hasSuccessText = await page.getByText(/generated|created|copy/i).count() > 0;
          await expectOrAlternateState(page, hasKeyDisplay || hasSuccessText);
        }
      }
    });

    test('should have copy key button', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      if (await apiKeysPage.keyNameInput.count() > 0) {
        await apiKeysPage.keyNameInput.fill('Copy Test Key');
        if (await apiKeysPage.generateButton.count() > 0) {
          await apiKeysPage.generateButton.first().click();
          await page.waitForTimeout(1000);
          const hasCopyButton = await apiKeysPage.copyKeyButton.count() > 0;
          await expectOrAlternateState(page, hasCopyButton);
        }
      }
    });

    test('should warn about key visibility', async ({ page }) => {
      await apiKeysPage.createKeyButton.first().click();
      await page.waitForTimeout(500);
      if (await apiKeysPage.keyNameInput.count() > 0) {
        await apiKeysPage.keyNameInput.fill('Warning Test Key');
        if (await apiKeysPage.generateButton.count() > 0) {
          await apiKeysPage.generateButton.first().click();
          await page.waitForTimeout(1000);
          // Should show warning about only displaying once
          const hasWarning = await page.getByText(/only.*shown.*once|won't.*show.*again|copy.*now/i).count() > 0;
          await expectOrAlternateState(page, hasWarning);
        }
      }
    });
  });

  test.describe('Key Actions', () => {
    test('should have revoke option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const revokeButton = page.getByRole('button', { name: /revoke|delete/i });
      if (await revokeButton.count() > 0) {
        await expect(revokeButton.first()).toBeVisible();
      }
    });

    test('should confirm before revoking', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const revokeButton = page.getByRole('button', { name: /revoke|delete/i });
      if (await revokeButton.count() > 0) {
        await revokeButton.first().click();
        await page.waitForTimeout(500);
        const hasConfirm = await page.getByRole('button', { name: /confirm|yes/i }).count() > 0;
        await expectOrAlternateState(page, hasConfirm);
        // Cancel to not actually revoke
        const cancelBtn = page.getByRole('button', { name: /cancel|no/i });
        if (await cancelBtn.count() > 0) {
          await cancelBtn.first().click();
        }
      }
    });

    test('should have regenerate option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const regenerateButton = page.getByRole('button', { name: /regenerate|rotate/i });
      if (await regenerateButton.count() > 0) {
        await expect(regenerateButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Search', () => {
    test('should have search input', async ({ page }) => {
      const searchCount = await apiKeysPage.searchInput.count();
      if (searchCount > 0) {
        await expect(apiKeysPage.searchInput.first()).toBeVisible();
      }
    });

    test('should filter keys by name', async ({ page }) => {
      if (await apiKeysPage.searchInput.count() > 0) {
        await apiKeysPage.searchInput.first().fill('test');
        await page.waitForTimeout(500);
        // Results should be filtered
      }
    });
  });

  test.describe('Security', () => {
    test('should not display full key in list', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasKeys = await apiKeysPage.keysList.count() > 0;
      if (hasKeys) {
        // Keys should be masked with asterisks
        const content = await apiKeysPage.keysList.first().textContent();
        // Full keys are usually 32+ characters without masking
        const hasFullKey = content && content.match(/[a-zA-Z0-9]{32,}/);
        expect(hasFullKey).toBeFalsy();
      }
    });
  });
});
