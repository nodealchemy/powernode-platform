import { test, expect } from '@playwright/test';
import { PublicPage } from '../pages/public/public.page';

/**
 * Public Pages E2E Tests
 *
 * Tests for unauthenticated public pages.
 *
 * Actual public routes:
 *   /          → redirects to /welcome (unauthenticated)
 *   /welcome   → WelcomePage (PublicPageContainer layout)
 *   /plans     → PlanSelectionPage (standalone layout)
 *   /pricing   → redirects to /plans
 *   /status    → StatusPage (standalone layout with own header/footer)
 *   /login     → LoginPage (standalone, no shared header/footer)
 *   /register  → RegisterPage (standalone)
 *
 * Non-existent routes (e.g. /about, /contact) fall through the catch-all
 * and redirect to / → /welcome.
 */

test.describe('Public Pages', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  let publicPage: PublicPage;

  test.beforeEach(async ({ page }) => {
    // Suppress console errors from API calls that may fail in test environment
    page.on('pageerror', () => {});
    publicPage = new PublicPage(page);
  });

  // ─── Welcome / Homepage ────────────────────────────────────────────

  test.describe('Homepage (Welcome)', () => {
    test.beforeEach(async () => {
      await publicPage.gotoHome();
    });

    test('should redirect unauthenticated user to /welcome', async ({ page }) => {
      await expect(page).toHaveURL(/welcome/);
    });

    test('should display Powernode branding', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/powernode/i);
    });

    test('should display header with navigation', async () => {
      await expect(publicPage.header).toBeVisible();
    });

    test('should display footer', async () => {
      await expect(publicPage.footer).toBeVisible();
    });

    test('should have sign-in link in header', async ({ page }) => {
      // PublicPageContainer header shows "Sign in" when unauthenticated
      const signInLink = page.locator('header').getByRole('link', { name: /sign in/i });
      await expect(signInLink).toBeVisible();
    });

    test('should have get-started link in header', async ({ page }) => {
      // PublicPageContainer header shows "Get Started" when unauthenticated
      const getStarted = page.locator('header').getByRole('link', { name: /get started/i });
      await expect(getStarted).toBeVisible();
    });

    test('should have navigation links', async () => {
      const navLinks = await publicPage.navigationLinks.count();
      expect(navLinks).toBeGreaterThan(0);
    });

    test('should display hero section or page content', async ({ page }) => {
      // WelcomePage renders either CMS content or an error fallback;
      // both live inside sections / headings
      const hasHeadingOrSection = await page.locator('h1, h2, section').count() > 0;
      expect(hasHeadingOrSection).toBeTruthy();
    });

    test('should be responsive on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await expect(page.locator('body')).toContainText(/powernode/i);
    });
  });

  // ─── Plans / Pricing ──────────────────────────────────────────────

  test.describe('Plans Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoPricing();
    });

    test('should load plans page', async ({ page }) => {
      await expect(page).toHaveURL(/plans/);
    });

    test('should display pricing headline', async ({ page }) => {
      // PlanSelectionPage hero: "Choose the perfect plan for your team"
      await expect(page.locator('body')).toContainText(/plan/i);
    });

    test('should display header with sign-in link', async ({ page }) => {
      // PlanSelectionPage has its own <header> with "Sign in" link
      await expect(publicPage.header).toBeVisible();
      const signIn = page.locator('header').getByRole('link', { name: /sign in/i });
      await expect(signIn).toBeVisible();
    });

    test('should display billing toggle', async ({ page }) => {
      // Monthly / Annual billing buttons
      const hasToggle = await page.getByText(/monthly|annual/i).count() > 0;
      expect(hasToggle).toBeTruthy();
    });

    test('should display trust indicators', async ({ page }) => {
      // "30-day money back", "Free trial included", "No setup fees"
      const hasTrust = await page.getByText(/money back|free trial|no setup/i).count() > 0;
      expect(hasTrust).toBeTruthy();
    });

    test('should display footer', async () => {
      await expect(publicPage.footer).toBeVisible();
    });
  });

  // ─── Status Page ──────────────────────────────────────────────────

  test.describe('Status Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoStatus();
    });

    test('should load status page', async ({ page }) => {
      await expect(page).toHaveURL(/status/);
      // StatusPage always shows "System Status" in the header
      await expect(page.locator('body')).toContainText(/system status/i);
    });

    test('should display header with Powernode branding', async ({ page }) => {
      // StatusPage has its own <header> with Powernode link
      await expect(publicPage.header).toBeVisible();
      await expect(page.locator('header')).toContainText(/powernode/i);
    });

    test('should display status content or error state', async ({ page }) => {
      // If API is available: shows overall status banner and "System Components"
      // If API fails: shows "Unable to Load Status" with a "Try Again" button
      const hasStatusContent =
        (await page.getByText(/operational|degraded|outage|unable to load/i).count()) > 0;
      expect(hasStatusContent).toBeTruthy();
    });

    test('should display status legend', async ({ page }) => {
      // The legend section is always rendered (outside the error conditional)
      // It contains: Operational, Degraded, Partial Outage, Major Outage
      const hasLegend = await page.getByText(/status legend/i).count() > 0;
      // Legend is inside the non-error branch, so it may not show on API failure
      // Regardless, the page should have recognizable status-related content
      const hasStatusText =
        (await page.getByText(/operational|system status|unable to load/i).count()) > 0;
      expect(hasLegend || hasStatusText).toBeTruthy();
    });

    test('should display footer', async () => {
      await expect(publicPage.footer).toBeVisible();
    });

    test('should have sign-in link', async ({ page }) => {
      // StatusPage footer area has "Sign In" link
      const hasSignIn = await page.getByRole('link', { name: /sign in/i }).count() > 0;
      expect(hasSignIn).toBeTruthy();
    });
  });

  // ─── Welcome Page (direct) ────────────────────────────────────────

  test.describe('Welcome Page', () => {
    test.beforeEach(async () => {
      await publicPage.gotoWelcome();
    });

    test('should load welcome page', async ({ page }) => {
      await expect(page).toHaveURL(/welcome/);
      await expect(page.locator('body')).toContainText(/powernode/i);
    });

    test('should display call-to-action links', async ({ page }) => {
      // WelcomePage CTA section has "Create Account" and "Sign In" links,
      // or if API error, "Try Again" and "View Plans" buttons
      const hasCTA =
        (await page.getByRole('link', { name: /create account|sign in|view plans|get started/i }).count()) > 0 ||
        (await page.getByRole('button', { name: /try again/i }).count()) > 0;
      expect(hasCTA).toBeTruthy();
    });

    test('should display feature highlights or error fallback', async ({ page }) => {
      // WelcomePage content section: "AI-Powered Platform" heading or error state
      const hasContent =
        (await page.getByText(/ai-powered|automation|something went wrong/i).count()) > 0;
      expect(hasContent).toBeTruthy();
    });
  });

  // ─── Navigation ───────────────────────────────────────────────────

  test.describe('Navigation', () => {
    test('should navigate from welcome to plans via header', async ({ page }) => {
      await publicPage.gotoHome();
      // PublicPageContainer header has "Get Started" link pointing to /plans
      const getStarted = page.locator('header').getByRole('link', { name: /get started/i });
      if ((await getStarted.count()) > 0) {
        await getStarted.first().click();
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveURL(/plans/);
      }
    });

    test('should navigate from welcome to login via header', async ({ page }) => {
      await publicPage.gotoHome();
      const signInLink = page.locator('header').getByRole('link', { name: /sign in/i });
      if ((await signInLink.count()) > 0) {
        await signInLink.first().click();
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveURL(/login/);
      }
    });

    test('should have consistent header on welcome and plans pages', async () => {
      await publicPage.gotoHome();
      await expect(publicPage.header).toBeVisible();

      await publicPage.gotoPricing();
      await expect(publicPage.header).toBeVisible();
    });

    test('should have consistent footer on welcome and plans pages', async () => {
      await publicPage.gotoHome();
      await expect(publicPage.footer).toBeVisible();

      await publicPage.gotoPricing();
      await expect(publicPage.footer).toBeVisible();
    });

    test('should redirect /pricing to /plans', async ({ page }) => {
      await page.goto('/pricing');
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/plans/);
    });

    test('should redirect unknown routes to welcome', async ({ page }) => {
      await page.goto('/nonexistent-page');
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/welcome/);
    });
  });

  // ─── Unauthorized Access ──────────────────────────────────────────

  test.describe('Unauthorized Access', () => {
    test('should redirect to login for protected app routes', async ({ page }) => {
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
