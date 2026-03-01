import { Page, Locator } from '@playwright/test';

/**
 * Public Pages Object Model
 *
 * Covers actual public routes:
 *   /welcome (homepage redirect target)
 *   /plans   (pricing redirect target)
 *   /status
 *   /login
 *   /register
 */
export class PublicPage {
  readonly page: Page;
  readonly header: Locator;
  readonly footer: Locator;
  readonly loginButton: Locator;
  readonly signUpButton: Locator;
  readonly navigationLinks: Locator;

  constructor(page: Page) {
    this.page = page;
    this.header = page.locator('header').first();
    this.footer = page.locator('footer').first();
    this.loginButton = page.getByRole('link', { name: /login|sign in/i });
    this.signUpButton = page.getByRole('link', { name: /sign up|register|get started/i });
    this.navigationLinks = page.locator('header a, nav a');
  }

  async gotoHome() {
    await this.page.goto('/');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoPricing() {
    await this.page.goto('/plans');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoStatus() {
    await this.page.goto('/status');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoWelcome() {
    await this.page.goto('/welcome');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoLogin() {
    await this.page.goto('/login');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoRegister() {
    await this.page.goto('/register');
    await this.page.waitForLoadState('networkidle');
  }
}
