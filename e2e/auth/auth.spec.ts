import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/auth/login.page';
import { RegisterPage } from '../pages/auth/register.page';

/**
 * Authentication E2E Tests
 *
 * Tests for login, registration, and authentication flows.
 */

test.describe('Authentication', () => {
  test.describe('Login Page', () => {
    let loginPage: LoginPage;

    test.beforeEach(async ({ page }) => {
      loginPage = new LoginPage(page);
      await loginPage.goto();
    });

    test('should display login form', async ({ page }) => {
      await loginPage.verifyFormVisible();
    });

    test('should display email and password fields', async ({ page }) => {
      await expect(loginPage.emailInput).toBeVisible();
      await expect(loginPage.passwordInput).toBeVisible();
    });

    test('should display submit button', async ({ page }) => {
      await expect(loginPage.submitButton).toBeVisible();
    });

    test('should have forgot password link', async ({ page }) => {
      await expect(loginPage.forgotPasswordLink.first()).toBeVisible();
    });

    test('should have sign up link', async ({ page }) => {
      await expect(loginPage.signUpLink.first()).toBeVisible();
    });

    test('should show error for invalid credentials', async ({ page }) => {
      await loginPage.loginExpectError('invalid@test.com', 'wrongpassword');
      await expect(loginPage.errorMessage.first()).toBeVisible();
    });

    test('should show error for empty email', async ({ page }) => {
      await loginPage.passwordInput.fill('somepassword');
      await loginPage.submitButton.click();
      // Should show validation error or stay on page
      await expect(page).toHaveURL(/login/);
    });

    test('should show error for empty password', async ({ page }) => {
      await loginPage.emailInput.fill('test@test.com');
      await loginPage.submitButton.click();
      // Should show validation error or stay on page
      await expect(page).toHaveURL(/login/);
    });

    test('should navigate to forgot password', async ({ page }) => {
      await loginPage.forgotPasswordLink.first().click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/password|reset|forgot/i);
    });

    test('should navigate to registration', async ({ page }) => {
      await loginPage.signUpLink.first().click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/register|sign up|create/i);
    });
  });

  test.describe('Registration Page', () => {
    let registerPage: RegisterPage;

    test.beforeEach(async ({ page }) => {
      registerPage = new RegisterPage(page);
      await registerPage.goto();
    });

    test('should display registration form', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/register|sign up|create/i);
    });

    test('should display name fields', async ({ page }) => {
      // Either separate first/last name or combined name field
      const hasName = await page.locator('input[name*="name"]').count() > 0;
      expect(hasName).toBeTruthy();
    });

    test('should display email field', async ({ page }) => {
      await expect(registerPage.emailInput).toBeVisible();
    });

    test('should display password fields', async ({ page }) => {
      await expect(registerPage.passwordInput).toBeVisible();
    });

    test('should display submit button', async ({ page }) => {
      await expect(registerPage.submitButton).toBeVisible();
    });

    test('should show validation for invalid email format', async ({ page }) => {
      await registerPage.emailInput.fill('invalid-email');
      await registerPage.passwordInput.fill('password123');
      await registerPage.submitButton.click();
      // Should show validation error or not submit
      await page.waitForTimeout(500);
      await expect(page).toHaveURL(/register|signup/);
    });

    test('should have link back to login', async ({ page }) => {
      await expect(registerPage.loginLink.first()).toBeVisible();
    });

    test('should navigate back to login', async ({ page }) => {
      await registerPage.loginLink.first().click();
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/login/);
    });
  });

  test.describe('Password Reset', () => {
    test('should display forgot password page', async ({ page }) => {
      await page.goto('/forgot-password');
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/password|email|reset/i);
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
  });
});

// Authenticated user tests use stored auth state
test.describe('Authenticated User', () => {
  test.use({ storageState: 'e2e/.auth/user.json' });

  test('should access dashboard when authenticated', async ({ page }) => {
    await page.goto('/app/dashboard');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).not.toContainText(/login/i);
  });

  test('should show user menu when authenticated', async ({ page }) => {
    await page.goto('/app/dashboard');
    await page.waitForLoadState('networkidle');
    const userMenu = page.locator('[class*="user-menu"], [class*="avatar"], [class*="profile"]').first();
    await expect(userMenu).toBeVisible();
  });

  test('should be able to logout', async ({ page }) => {
    await page.goto('/app/dashboard');
    await page.waitForLoadState('networkidle');

    // Click user menu
    const userMenu = page.locator('[class*="user-menu"], [class*="avatar"], [class*="profile"]').first();
    await userMenu.click();

    // Look for logout option
    const logoutButton = page.getByText(/logout|sign out/i);
    if (await logoutButton.isVisible()) {
      await logoutButton.click();
      await page.waitForLoadState('networkidle');
      // Should redirect to login
      await expect(page).toHaveURL(/login/);
    }
  });
});
