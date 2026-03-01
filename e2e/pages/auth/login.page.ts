import { Page, Locator, expect } from '@playwright/test';

/**
 * Login Page Object Model
 *
 * Matches the actual LoginPage component at:
 *   frontend/src/pages/public/LoginPage.tsx
 *
 * Key selectors from the component:
 *   - data-testid="email-input"
 *   - data-testid="password-input"
 *   - data-testid="login-submit-btn"
 *   - data-testid="forgot-password-link"
 *   - data-testid="remember-me-checkbox"
 */
export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;
  readonly forgotPasswordLink: Locator;
  readonly signUpLink: Locator;
  readonly rememberMeCheckbox: Locator;

  constructor(page: Page) {
    this.page = page;
    // Use data-testid selectors first, then fallback to attribute selectors
    this.emailInput = page.locator('[data-testid="email-input"], input[name="email"]').first();
    this.passwordInput = page.locator('[data-testid="password-input"], input[name="password"]').first();
    this.submitButton = page.locator('[data-testid="login-submit-btn"], button[type="submit"]').first();
    // Error can appear as inline div or as a notification toast
    this.errorMessage = page.locator('[class*="bg-theme-error"], [class*="error"], [role="alert"]').first();
    this.forgotPasswordLink = page.locator('[data-testid="forgot-password-link"]');
    // The "sign up" link text is "Create your account" pointing to /plans
    this.signUpLink = page.getByText(/create your account|sign up|register/i);
    this.rememberMeCheckbox = page.locator('[data-testid="remember-me-checkbox"], input[type="checkbox"]').first();
  }

  async goto() {
    await this.page.goto('/login');
    await this.page.waitForLoadState('networkidle');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
    await this.page.waitForURL(/\/(app|dashboard)/, { timeout: 30000 });
  }

  async loginExpectError(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
    // Wait for either an inline error or a notification toast
    await this.page.waitForTimeout(2000);
  }

  async verifyFormVisible() {
    await expect(this.emailInput).toBeVisible();
    await expect(this.passwordInput).toBeVisible();
    await expect(this.submitButton).toBeVisible();
  }

  async clickForgotPassword() {
    await this.forgotPasswordLink.click();
  }

  async clickSignUp() {
    await this.signUpLink.click();
  }
}
