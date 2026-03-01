import { Page, Locator, expect } from '@playwright/test';

/**
 * Registration Page Object Model
 *
 * Matches the actual RegisterPage component at:
 *   frontend/src/pages/public/RegisterPage.tsx
 *
 * IMPORTANT: The register page requires a ?plan=<id> query param.
 * Without it, it redirects to /plans. Tests should account for this.
 *
 * Key selectors from the component:
 *   - data-testid="account-name-input" (company/account name)
 *   - data-testid="name-input" (full name, single field)
 *   - data-testid="register-email-input"
 *   - data-testid="register-password-input"
 *   - data-testid="register-submit-btn"
 *   - data-testid="selected-plan"
 */
export class RegisterPage {
  readonly page: Page;
  readonly nameInput: Locator;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly accountNameInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;
  readonly loginLink: Locator;

  constructor(page: Page) {
    this.page = page;
    this.nameInput = page.locator('[data-testid="name-input"], input[name="name"]').first();
    this.emailInput = page.locator('[data-testid="register-email-input"], input[name="email"]').first();
    this.passwordInput = page.locator('[data-testid="register-password-input"], input[name="password"]').first();
    this.accountNameInput = page.locator('[data-testid="account-name-input"], input[name="accountName"]').first();
    this.submitButton = page.locator('[data-testid="register-submit-btn"], button[type="submit"]').first();
    this.errorMessage = page.locator('[class*="bg-theme-error"], [class*="error"], [role="alert"]').first();
    // "Already have an account? Sign in"
    this.loginLink = page.getByText(/sign in|login|already have/i);
  }

  /**
   * Navigate to the register page.
   * Note: Without a plan query param, this redirects to /plans.
   * The test should account for this behavior.
   */
  async goto() {
    await this.page.goto('/register');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoWithPlan(planId: string, billing: 'monthly' | 'yearly' = 'monthly') {
    await this.page.goto(`/register?plan=${planId}&billing=${billing}`);
    await this.page.waitForLoadState('networkidle');
  }

  async verifyFormVisible() {
    await expect(this.emailInput).toBeVisible();
    await expect(this.passwordInput).toBeVisible();
    await expect(this.submitButton).toBeVisible();
  }
}
