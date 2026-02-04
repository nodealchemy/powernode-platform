import { Page, Locator, expect } from '@playwright/test';

/**
 * Account Profile Page Object Model
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
    this.firstNameInput = page.locator('input[name="firstName"], input[name="first_name"]');
    this.lastNameInput = page.locator('input[name="lastName"], input[name="last_name"]');
    this.emailInput = page.locator('input[type="email"], input[name="email"]');
    this.phoneInput = page.locator('input[type="tel"], input[name="phone"]');
    this.avatarUpload = page.locator('input[type="file"]');
    this.saveButton = page.getByRole('button', { name: /save|update/i });
    this.changePasswordButton = page.getByRole('button', { name: /change password/i });
    this.deleteAccountButton = page.getByRole('button', { name: /delete account/i });
  }

  async goto() {
    await this.page.goto('/app/account/profile');
    await this.page.waitForLoadState('networkidle');
  }

  async updateProfile(data: { firstName?: string; lastName?: string; phone?: string }) {
    if (data.firstName) await this.firstNameInput.fill(data.firstName);
    if (data.lastName) await this.lastNameInput.fill(data.lastName);
    if (data.phone) await this.phoneInput.fill(data.phone);
    await this.saveButton.click();
  }

  async verifyProfileData(data: { firstName?: string; lastName?: string }) {
    if (data.firstName) {
      await expect(this.firstNameInput).toHaveValue(data.firstName);
    }
    if (data.lastName) {
      await expect(this.lastNameInput).toHaveValue(data.lastName);
    }
  }
}
