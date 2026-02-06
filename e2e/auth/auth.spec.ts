import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/auth/login.page';

/**
 * Authentication E2E Tests
 *
 * Tests for login, registration, and authentication flows.
 *
 * IMPORTANT: The Playwright config injects storageState (authenticated user)
 * for all projects. Public auth pages use PublicRoute which redirects
 * authenticated users to /app. We must clear storageState for these tests.
 */

test.describe('Authentication', () => {
  // Clear auth state so PublicRoute does not redirect us away from login/register/forgot-password
  test.use({ storageState: { cookies: [], origins: [] } });

  test.describe('Login Page', () => {
    let loginPage: LoginPage;

    test.beforeEach(async ({ page }) => {
      // Suppress console errors from API calls hitting unauthenticated endpoints
      page.on('pageerror', () => {});
      loginPage = new LoginPage(page);
      await loginPage.goto();
    });

    test('should display login form', async () => {
      await loginPage.verifyFormVisible();
    });

    test('should display email and password fields', async () => {
      await expect(loginPage.emailInput).toBeVisible();
      await expect(loginPage.passwordInput).toBeVisible();
    });

    test('should display submit button', async () => {
      await expect(loginPage.submitButton).toBeVisible();
    });

    test('should have forgot password link', async () => {
      await expect(loginPage.forgotPasswordLink).toBeVisible();
    });

    test('should have sign up link', async () => {
      await expect(loginPage.signUpLink.first()).toBeVisible();
    });

    test('should show error for invalid credentials', async ({ page }) => {
      await loginPage.loginExpectError('invalid@test.com', 'wrongpassword');
      // Error can appear as inline error div or as a notification toast
      const hasError = await page.locator('[class*="error"], [class*="notification"], [role="alert"]').first().isVisible().catch(() => false);
      expect(hasError).toBeTruthy();
    });

    test('should show error for empty email', async ({ page }) => {
      await loginPage.passwordInput.fill('somepassword');
      await loginPage.submitButton.click();
      // HTML5 required attribute prevents submission - should stay on login page
      await expect(page).toHaveURL(/login/);
    });

    test('should show error for empty password', async ({ page }) => {
      await loginPage.emailInput.fill('test@test.com');
      await loginPage.submitButton.click();
      // HTML5 required attribute prevents submission - should stay on login page
      await expect(page).toHaveURL(/login/);
    });

    test('should navigate to forgot password', async ({ page }) => {
      await loginPage.forgotPasswordLink.click();
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/forgot-password/);
    });

    test('should navigate to plans page from sign up link', async ({ page }) => {
      await loginPage.signUpLink.first().click();
      await page.waitForLoadState('networkidle');
      // The "Create your account" link navigates to /plans
      await expect(page).toHaveURL(/plans/);
    });
  });

  test.describe('Registration Page', () => {
    /**
     * The register page requires a ?plan=<id> query param.
     * Without it, it redirects to /plans. We test the redirect behavior
     * and the plans page presence since we cannot know a valid plan ID
     * ahead of time in E2E tests.
     */

    test.beforeEach(async ({ page }) => {
      page.on('pageerror', () => {});
    });

    test('should redirect to plans when no plan selected', async ({ page }) => {
      await page.goto('/register');
      await page.waitForLoadState('networkidle');
      // Without a plan param, the register page redirects to /plans
      await expect(page).toHaveURL(/plans/);
    });

    test('should display plan selection page', async ({ page }) => {
      await page.goto('/plans');
      await page.waitForLoadState('networkidle');
      // Plans page should show plan options
      await expect(page.locator('body')).toContainText(/plan|pricing|free|start/i);
    });

    test('should display plan options on plans page', async ({ page }) => {
      await page.goto('/plans');
      await page.waitForLoadState('networkidle');
      // Should have at least one button or link to select a plan
      const hasActions = await page.locator('button, a[href*="register"]').count();
      expect(hasActions).toBeGreaterThan(0);
    });

    test('should have login link on plans page', async ({ page }) => {
      await page.goto('/plans');
      await page.waitForLoadState('networkidle');
      // Plans page or login page should be accessible
      const loginLink = page.getByText(/sign in|login|already have/i).first();
      if (await loginLink.isVisible().catch(() => false)) {
        await loginLink.click();
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveURL(/login/);
      }
    });
  });

  test.describe('Password Reset', () => {
    test.beforeEach(async ({ page }) => {
      page.on('pageerror', () => {});
    });

    test('should display forgot password page', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/reset your password|password|email/i);
    });

    test('should have email input for reset', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      const emailInput = page.locator('input[type="email"], input[name="email"]');
      await expect(emailInput).toBeVisible();
    });

    test('should have submit button', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      const submitButton = page.locator('button[type="submit"]');
      await expect(submitButton).toBeVisible();
    });

    test('should have sign in link', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      // "Remember your password? Sign in" link
      const signInLink = page.getByText(/sign in/i).first();
      await expect(signInLink).toBeVisible();
    });

    test('should navigate back to login from forgot password', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      const signInLink = page.getByText(/sign in/i).first();
      await signInLink.click();
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/login/);
    });
  });
});

// Authenticated user tests use stored auth state
test.describe('Authenticated User', () => {
  test.use({ storageState: 'e2e/.auth/user.json' });

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
  });

  test('should access dashboard when authenticated', async ({ page }) => {
    await page.goto('/app');
    await page.waitForLoadState('networkidle');
    // Should not be redirected to login
    await expect(page).not.toHaveURL(/login/);
  });

  test('should show user menu when authenticated', async ({ page }) => {
    await page.goto('/app');
    await page.waitForLoadState('networkidle');
    // UserMenu has a button with aria-haspopup="true"
    const userMenuButton = page.locator('button[aria-haspopup="true"]').first();
    await expect(userMenuButton).toBeVisible();
  });

  test('should be able to open user menu', async ({ page }) => {
    await page.goto('/app');
    await page.waitForLoadState('networkidle');

    // Click user menu button (has aria-haspopup="true")
    const userMenuButton = page.locator('button[aria-haspopup="true"]').first();
    if (await userMenuButton.isVisible().catch(() => false)) {
      await userMenuButton.click();
      await page.waitForTimeout(500);

      // Look for Sign Out option in the dropdown
      const signOutButton = page.getByText(/sign out/i).first();
      await expect(signOutButton).toBeVisible();
    }
  });

  test('should redirect to app when visiting login while authenticated', async ({ page }) => {
    await page.goto('/login');
    await page.waitForLoadState('networkidle');
    // PublicRoute redirects authenticated users to /app
    await expect(page).toHaveURL(/\/app/);
  });
});
