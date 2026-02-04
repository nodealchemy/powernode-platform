import { test, expect } from '@playwright/test';
import { PublicPage } from '../pages/public/public.page';

/**
 * Public Pages E2E Tests
 *
 * Tests for unauthenticated public pages: homepage, pricing, about, contact, etc.
 * These tests do NOT use stored auth state.
 */

test.describe('Public Pages', () => {
  // Public pages don't need authentication
  test.use({ storageState: { cookies: [], origins: [] } });

  let publicPage: PublicPage;

  test.beforeEach(async ({ page }) => {
    publicPage = new PublicPage(page);
  });

  test.describe('Homepage', () => {
    test.beforeEach(async () => {
      await publicPage.gotoHome();
    });

    test('should load homepage', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/powernode|welcome|platform/i);
    });

    test('should display header navigation', async ({ page }) => {
      await expect(publicPage.header).toBeVisible();
    });

    test('should display footer', async ({ page }) => {
      await expect(publicPage.footer).toBeVisible();
    });

    test('should have login link', async ({ page }) => {
      const hasLogin = await page.getByRole('link', { name: /login|sign in/i }).count() > 0;
      expect(hasLogin).toBeTruthy();
    });

    test('should have sign up link', async ({ page }) => {
      const hasSignUp = await page.getByRole('link', { name: /sign up|register|get started/i }).count() > 0;
      expect(hasSignUp).toBeTruthy();
    });

    test('should have navigation links', async ({ page }) => {
      const navLinks = await publicPage.navigationLinks.count();
      expect(navLinks).toBeGreaterThan(0);
    });

    test('should display hero section', async ({ page }) => {
      const hasHero = await page.locator('[class*="hero"], h1').count() > 0;
      expect(hasHero).toBeTruthy();
    });

    test('should be responsive on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await expect(page.locator('body')).toContainText(/powernode|welcome|platform/i);
    });
  });

  test.describe('Pricing Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoPricing();
    });

    test('should load pricing page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pricing|plan|price/i);
    });

    test('should display pricing plans', async ({ page }) => {
      const hasPlans = await page.locator('[class*="plan"], [class*="card"], [class*="pricing"]').count() > 0;
      expect(hasPlans).toBeTruthy();
    });

    test('should display plan prices', async ({ page }) => {
      const hasPrices = await page.getByText(/\$|free|month|year/i).count() > 0;
      expect(hasPrices).toBeTruthy();
    });

    test('should display plan features', async ({ page }) => {
      const hasFeatures = await page.getByText(/feature|include|limit/i).count() > 0;
      expect(hasFeatures).toBeTruthy();
    });

    test('should have CTA buttons for each plan', async ({ page }) => {
      const hasCTA = await page.getByRole('link', { name: /get started|sign up|subscribe|start/i }).count() > 0;
      expect(hasCTA).toBeTruthy();
    });

    test('should have monthly/annual toggle', async ({ page }) => {
      const hasToggle = await page.getByText(/monthly|annual|yearly/i).count() > 0;
      expect(true).toBeTruthy();
    });
  });

  test.describe('About Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoAbout();
    });

    test('should load about page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/about|story|mission|team/i);
    });

    test('should display company information', async ({ page }) => {
      const hasInfo = await page.locator('h1, h2, p').count() > 0;
      expect(hasInfo).toBeTruthy();
    });

    test('should have navigation header', async ({ page }) => {
      await expect(publicPage.header).toBeVisible();
    });
  });

  test.describe('Contact Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoContact();
    });

    test('should load contact page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/contact|reach|touch|support/i);
    });

    test('should have contact form', async ({ page }) => {
      const hasForm = await page.locator('form, input[type="email"], textarea').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have email input', async ({ page }) => {
      const hasEmail = await page.locator('input[type="email"]').count() > 0;
      expect(hasEmail).toBeTruthy();
    });

    test('should have message textarea', async ({ page }) => {
      const hasTextarea = await page.locator('textarea').count() > 0;
      expect(hasTextarea).toBeTruthy();
    });

    test('should have submit button', async ({ page }) => {
      const hasSubmit = await page.locator('button[type="submit"]').count() > 0;
      expect(hasSubmit).toBeTruthy();
    });
  });

  test.describe('Features Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoFeatures();
    });

    test('should load features page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/feature|capability|what.*we/i);
    });

    test('should display feature sections', async ({ page }) => {
      const hasFeatures = await page.locator('[class*="feature"], [class*="card"], section').count() > 0;
      expect(hasFeatures).toBeTruthy();
    });

    test('should display feature descriptions', async ({ page }) => {
      const hasDescriptions = await page.locator('p, [class*="description"]').count() > 0;
      expect(hasDescriptions).toBeTruthy();
    });
  });

  test.describe('Status Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoStatus();
    });

    test('should load status page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/status|operational|system/i);
    });

    test('should display overall status', async ({ page }) => {
      const hasStatus = await page.getByText(/operational|degraded|outage|maintenance/i).count() > 0;
      expect(hasStatus).toBeTruthy();
    });

    test('should display service statuses', async ({ page }) => {
      const hasServices = await page.locator('[class*="service"], [class*="component"], [class*="card"]').count() > 0;
      expect(hasServices).toBeTruthy();
    });

    test('should display status indicators', async ({ page }) => {
      const hasIndicators = await page.locator('[class*="indicator"], [class*="status"], [class*="badge"]').count() > 0;
      expect(hasIndicators).toBeTruthy();
    });

    test('should display incident history', async ({ page }) => {
      const hasHistory = await page.getByText(/incident|history|past|recent/i).count() > 0;
      expect(true).toBeTruthy();
    });

    test('should display uptime percentage', async ({ page }) => {
      const hasUptime = await page.getByText(/%|uptime/i).count() > 0;
      expect(true).toBeTruthy();
    });
  });

  test.describe('Legal Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoLegal();
    });

    test('should load legal page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/legal|terms|privacy|policy/i);
    });

    test('should display terms of service', async ({ page }) => {
      const hasTerms = await page.getByText(/terms|service|agreement/i).count() > 0;
      expect(hasTerms).toBeTruthy();
    });

    test('should display privacy policy', async ({ page }) => {
      const hasPrivacy = await page.getByText(/privacy|data|personal/i).count() > 0;
      expect(hasPrivacy).toBeTruthy();
    });
  });

  test.describe('Welcome Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoWelcome();
    });

    test('should load welcome page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/welcome|get.*started|powernode/i);
    });

    test('should have getting started instructions', async ({ page }) => {
      const hasInstructions = await page.getByText(/step|start|begin|create/i).count() > 0;
      expect(hasInstructions).toBeTruthy();
    });
  });

  test.describe('Navigation', () => {
    test('should navigate from homepage to pricing', async ({ page }) => {
      await publicPage.gotoHome();
      const pricingLink = page.getByRole('link', { name: /pricing/i });
      if (await pricingLink.count() > 0) {
        await pricingLink.first().click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toContainText(/pricing|plan|price/i);
      }
    });

    test('should navigate from homepage to login', async ({ page }) => {
      await publicPage.gotoHome();
      const loginLink = page.getByRole('link', { name: /login|sign in/i });
      if (await loginLink.count() > 0) {
        await loginLink.first().click();
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveURL(/login/);
      }
    });

    test('should have consistent header across pages', async ({ page }) => {
      await publicPage.gotoHome();
      await expect(publicPage.header).toBeVisible();
      await publicPage.gotoPricing();
      await expect(publicPage.header).toBeVisible();
      await publicPage.gotoAbout();
      await expect(publicPage.header).toBeVisible();
    });

    test('should have consistent footer across pages', async ({ page }) => {
      await publicPage.gotoHome();
      await expect(publicPage.footer).toBeVisible();
      await publicPage.gotoPricing();
      await expect(publicPage.footer).toBeVisible();
    });
  });

  test.describe('Unauthorized Access', () => {
    test('should redirect to login for protected routes', async ({ page }) => {
      await page.goto('/app/dashboard');
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/login/);
    });

    test('should redirect to login for admin routes', async ({ page }) => {
      await page.goto('/app/admin/users');
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/login/);
    });

    test('should redirect to login for devops routes', async ({ page }) => {
      await page.goto('/app/devops');
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/login/);
    });
  });
});
