import { Page, Locator, expect } from '@playwright/test';

/**
 * Registration Page Object Model
 */
export class RegisterPage {
  readonly page: Page;
  readonly firstNameInput: Locator;
  readonly lastNameInput: Locator;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly confirmPasswordInput: Locator;
  readonly companyNameInput: Locator;
  readonly termsCheckbox: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;
  readonly loginLink: Locator;

  constructor(page: Page) {
    this.page = page;
    this.firstNameInput = page.locator('input[name="firstName"], input[name="first_name"]');
    this.lastNameInput = page.locator('input[name="lastName"], input[name="last_name"]');
    this.emailInput = page.locator('input[type="email"], input[name="email"]');
    this.passwordInput = page.locator('input[name="password"]').first();
    this.confirmPasswordInput = page.locator('input[name="confirmPassword"], input[name="password_confirmation"]');
    this.companyNameInput = page.locator('input[name="companyName"], input[name="company"]');
    this.termsCheckbox = page.locator('input[type="checkbox"]');
    this.submitButton = page.locator('button[type="submit"]');
    this.errorMessage = page.locator('[class*="error"], [role="alert"]');
    this.loginLink = page.getByText(/sign in|login|already have/i);
  }

  async goto() {
    await this.page.goto('/register');
    await this.page.waitForLoadState('networkidle');
  }

  async register(data: {
    firstName: string;
    lastName: string;
    email: string;
    password: string;
    company?: string;
  }) {
    await this.firstNameInput.fill(data.firstName);
    await this.lastNameInput.fill(data.lastName);
    await this.emailInput.fill(data.email);
    await this.passwordInput.fill(data.password);
    if (await this.confirmPasswordInput.isVisible()) {
      await this.confirmPasswordInput.fill(data.password);
    }
    if (data.company && await this.companyNameInput.isVisible()) {
      await this.companyNameInput.fill(data.company);
    }
    if (await this.termsCheckbox.isVisible()) {
      await this.termsCheckbox.check();
    }
    await this.submitButton.click();
  }

  async verifyFormVisible() {
    await expect(this.emailInput).toBeVisible();
    await expect(this.passwordInput).toBeVisible();
    await expect(this.submitButton).toBeVisible();
  }
}
