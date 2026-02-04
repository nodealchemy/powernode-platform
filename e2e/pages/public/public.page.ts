import { Page, Locator, expect } from '@playwright/test';

/**
 * Public Pages Object Model
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
    this.header = page.locator('header, [class*="header"]').first();
    this.footer = page.locator('footer, [class*="footer"]').first();
    this.loginButton = page.getByRole('link', { name: /login|sign in/i });
    this.signUpButton = page.getByRole('link', { name: /sign up|register|get started/i });
    this.navigationLinks = page.locator('header a, nav a');
  }

  async gotoHome() {
    await this.page.goto('/');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoPricing() {
    await this.page.goto('/pricing');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoAbout() {
    await this.page.goto('/about');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoContact() {
    await this.page.goto('/contact');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoFeatures() {
    await this.page.goto('/features');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoStatus() {
    await this.page.goto('/status');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoLegal() {
    await this.page.goto('/legal');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoWelcome() {
    await this.page.goto('/welcome');
    await this.page.waitForLoadState('networkidle');
  }
}
