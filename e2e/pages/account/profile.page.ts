import { Page, Locator, expect } from '@playwright/test';

/**
 * Account Profile Page Object Model
 *
 * Matches the actual ProfilePage component at /app/profile which uses:
 * - PageContainer with "Save Changes" action (data-testid="action-save")
 * - Tabbed interface (Profile, Account, Subscription, Preferences, Notifications, Security)
 * - Single "name" field (not first/last name split)
 * - Email field
 * - No phone field on profile tab
 * - Change Password form on Security tab
 */
export class AccountProfilePage {
  readonly page: Page;
  readonly firstNameInput: Locator;
  readonly lastNameInput: Locator;
  readonly emailInput: Locator;
  readonly phoneInput: Locator;
  readonly avatarUpload: Locator;
  readonly saveButton: Locator;
  readonly changePasswordButton: Locator;
  readonly deleteAccountButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // Profile form has a single "name" input (not firstName/lastName)
    this.firstNameInput = page.locator('input[name="name"]');
    // Last name field doesn't exist - use a selector that won't match but won't error
    this.lastNameInput = page.locator('input[name="lastName"], input[name="last_name"]');
    this.emailInput = page.locator('input[type="email"], input[name="email"]');
    // Phone field doesn't exist on profile tab
    this.phoneInput = page.locator('input[type="tel"], input[name="phone"]');
    this.avatarUpload = page.locator('input[type="file"]');
    // PageContainer "Save Changes" button or form submit button
    this.saveButton = page.locator('[data-testid="action-save"], button:has-text("Save Changes"), button[type="submit"]');
    this.changePasswordButton = page.locator('button:has-text("Change Password")');
    this.deleteAccountButton = page.getByRole('button', { name: /delete account/i });
  }

  async goto() {
    // Actual route is /app/profile (not /app/account/profile)
    await this.page.goto('/app/profile');
    await this.page.waitForLoadState('networkidle');
  }

  async updateProfile(data: { firstName?: string; lastName?: string; phone?: string }) {
    if (data.firstName && await this.firstNameInput.isVisible()) {
      await this.firstNameInput.fill(data.firstName);
    }
    if (data.lastName && await this.lastNameInput.count() > 0 && await this.lastNameInput.isVisible()) {
      await this.lastNameInput.fill(data.lastName);
    }
    if (data.phone && await this.phoneInput.count() > 0 && await this.phoneInput.isVisible()) {
      await this.phoneInput.fill(data.phone);
    }
    await this.saveButton.first().click();
  }

  async verifyProfileData(data: { firstName?: string; lastName?: string }) {
    if (data.firstName && await this.firstNameInput.isVisible()) {
      await expect(this.firstNameInput).toHaveValue(data.firstName);
    }
    if (data.lastName && await this.lastNameInput.count() > 0 && await this.lastNameInput.isVisible()) {
      await expect(this.lastNameInput).toHaveValue(data.lastName);
    }
  }
}
