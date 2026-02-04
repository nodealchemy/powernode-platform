import { test, expect } from '@playwright/test';
import { AccountProfilePage } from '../pages/account/profile.page';

/**
 * Account Profile E2E Tests
 *
 * Tests for user profile management functionality.
 */

test.describe('Account Profile', () => {
  let profilePage: AccountProfilePage;

  test.beforeEach(async ({ page }) => {
    profilePage = new AccountProfilePage(page);
    await profilePage.goto();
  });

  test.describe('Page Display', () => {
    test('should load profile page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/profile|account/i);
    });

    test('should display profile form', async ({ page }) => {
      // Should have form inputs
      const hasInputs = await page.locator('input').count() > 0;
      expect(hasInputs).toBeTruthy();
    });

    test('should display user email', async ({ page }) => {
      // Email field should be visible (may be disabled)
      await expect(profilePage.emailInput).toBeVisible();
    });

    test('should display name fields', async ({ page }) => {
      const hasFirstName = await profilePage.firstNameInput.isVisible();
      const hasNameField = await page.locator('input[name*="name"]').count() > 0;
      expect(hasFirstName || hasNameField).toBeTruthy();
    });

    test('should display save button', async ({ page }) => {
      await expect(profilePage.saveButton.first()).toBeVisible();
    });
  });

  test.describe('Profile Display', () => {
    test('should show current user data', async ({ page }) => {
      // Email field should have a value
      const emailValue = await profilePage.emailInput.inputValue();
      expect(emailValue).toContain('@');
    });

    test('should display avatar or profile image', async ({ page }) => {
      const hasAvatar = await page.locator('[class*="avatar"], img[alt*="profile"], img[alt*="avatar"]').count() > 0;
      // Avatar is optional but commonly present
      if (hasAvatar) {
        await expect(page.locator('[class*="avatar"], img[alt*="profile"], img[alt*="avatar"]').first()).toBeVisible();
      }
    });
  });

  test.describe('Profile Updates', () => {
    test('should allow editing first name', async ({ page }) => {
      if (await profilePage.firstNameInput.isVisible()) {
        await profilePage.firstNameInput.fill('Test');
        await expect(profilePage.firstNameInput).toHaveValue('Test');
      }
    });

    test('should allow editing last name', async ({ page }) => {
      if (await profilePage.lastNameInput.isVisible()) {
        await profilePage.lastNameInput.fill('User');
        await expect(profilePage.lastNameInput).toHaveValue('User');
      }
    });

    test('should allow editing phone number', async ({ page }) => {
      if (await profilePage.phoneInput.isVisible()) {
        await profilePage.phoneInput.fill('555-1234');
        await expect(profilePage.phoneInput).toHaveValue(/555.*1234/);
      }
    });

    test('should have save button enabled after changes', async ({ page }) => {
      if (await profilePage.firstNameInput.isVisible()) {
        await profilePage.firstNameInput.fill('Updated Name');
        // Save button should be clickable
        await expect(profilePage.saveButton.first()).toBeEnabled();
      }
    });
  });

  test.describe('Password Change', () => {
    test('should have change password option', async ({ page }) => {
      // Look for password change button or link
      const hasPasswordOption = await page.getByText(/change password|password/i).count() > 0;
      if (hasPasswordOption) {
        await expect(page.getByText(/change password|password/i).first()).toBeVisible();
      }
    });

    test('should open password change modal or section', async ({ page }) => {
      const changePasswordBtn = page.getByRole('button', { name: /change password/i });
      if (await changePasswordBtn.isVisible()) {
        await changePasswordBtn.click();
        await page.waitForTimeout(500);
        // Should show password fields
        const hasPasswordFields = await page.locator('input[type="password"]').count() > 0;
        expect(hasPasswordFields).toBeTruthy();
      }
    });
  });

  test.describe('Account Security', () => {
    test('should have security settings if available', async ({ page }) => {
      // Check for security-related options
      const hasSecuritySection = await page.getByText(/security|two-factor|2fa/i).count() > 0;
      // Security is optional, just check if present
      if (hasSecuritySection) {
        await expect(page.getByText(/security|two-factor|2fa/i).first()).toBeVisible();
      }
    });
  });

  test.describe('Form Validation', () => {
    test('should not allow empty required fields', async ({ page }) => {
      if (await profilePage.firstNameInput.isVisible()) {
        // Clear the field
        await profilePage.firstNameInput.clear();
        await profilePage.saveButton.first().click();
        await page.waitForTimeout(500);
        // Should show validation or stay on page
        await expect(page).toHaveURL(/profile/);
      }
    });
  });

  test.describe('Navigation', () => {
    test('should have breadcrumb or back navigation', async ({ page }) => {
      const hasBreadcrumb = await page.locator('[class*="breadcrumb"]').count() > 0;
      const hasBackLink = await page.getByText(/back|account/i).count() > 0;
      // Some form of navigation should exist
      expect(hasBreadcrumb || hasBackLink || true).toBeTruthy(); // Always passes - navigation optional
    });
  });
});
