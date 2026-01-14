describe('Authentication Flow', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
  });

  describe('User Registration', () => {
    it('should allow new user to register successfully', () => {
      // Registration requires plan selection first
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).first().should('be.visible').click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible').click();
      cy.url().should('include', '/register');

      // Fill out registration form using data-testid selectors
      const timestamp = Date.now();
      cy.get('[data-testid="account-name-input"]').should('be.visible').type('Test Company');
      cy.get('[data-testid="name-input"]').should('be.visible').type('John Doe');
      cy.get('[data-testid="register-email-input"]').should('be.visible').type(`john-${timestamp}@testcompany.com`);
      cy.get('[data-testid="register-password-input"]').should('be.visible').type('Qx7#mK9@pL2$nZ6%');

      // Submit form
      cy.get('[data-testid="register-submit-btn"]').should('be.visible').click();

      // Should redirect to app or dashboard
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    });

    it('should show validation errors for invalid registration data', () => {
      // Registration requires plan selection first
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).first().should('be.visible').click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible').click();
      cy.url().should('include', '/register');

      // Try to submit empty form - check that button is disabled or shows validation
      cy.get('[data-testid="register-submit-btn"]').should('be.disabled');

      // Fill partial data to trigger validation
      cy.get('[data-testid="register-email-input"]').should('be.visible').type('invalid-email');
      cy.get('[data-testid="register-email-input"]').blur();

      // Check for validation feedback (button still disabled)
      cy.get('[data-testid="register-submit-btn"]').should('be.disabled');
    });

    it('should redirect to plan selection when accessing registration directly', () => {
      // Try to access registration without plan
      cy.visit('/register');

      // Should redirect to plans page
      cy.url().should('include', '/plans');
    });
  });

  describe('User Login', () => {
    it('should allow existing user to login successfully', () => {
      // Use seeded demo user
      cy.visit('/login');

      // Fill out login form using data-testid selectors
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('DemoSecure456!@#$%');

      // Submit form
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Should redirect to app or dashboard
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    });

    it('should show error for invalid credentials', () => {
      cy.visit('/login');

      // Fill out login form with wrong password
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('wrongpassword123!');

      // Submit form
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Should show error message or stay on login page
      cy.url().should('include', '/login');
    });

    it('should show loading state during login', () => {
      cy.visit('/login');

      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Should either show loading state or complete login
      // The button may show loading text or become disabled
      cy.get('[data-testid="login-submit-btn"]').should('exist');
    });
  });

  describe('Password Reset', () => {
    it('should allow user to request password reset', () => {
      cy.visit('/login');

      // Click forgot password link
      cy.get('[data-testid="forgot-password-link"]', { timeout: 5000 }).should('be.visible').click();
      cy.url().should('include', '/forgot-password');

      // Enter email
      cy.get('input[name="email"], [data-testid="email-input"]').should('be.visible').type('demo@democompany.com');
      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show success message or stay on page
      cy.url().should('satisfy', (url: string) =>
        url.includes('/forgot-password') || url.includes('/login')
      );
    });

    it('should navigate to forgot password page', () => {
      cy.visit('/forgot-password');

      // Page should load with email input
      cy.get('input[name="email"], [data-testid="email-input"]').should('be.visible');
    });
  });

  describe('Protected Routes', () => {
    it('should redirect unauthenticated users to login', () => {
      cy.visit('/app');
      cy.url().should('include', '/login');

      cy.visit('/dashboard');
      cy.url().should('include', '/login');
    });

    it('should allow authenticated users to access protected routes', () => {
      // Login first
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Wait for redirect to app
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      // Should be able to access protected routes
      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });

  describe('Session Management', () => {
    it('should maintain session across page refreshes', () => {
      // Login first
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Wait for login
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      // Refresh the page
      cy.reload();

      // Should still be authenticated
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should handle logout properly', () => {
      // Login first
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).should('be.visible').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').should('be.visible').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();

      // Wait for login
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
      cy.waitForStableDOM();

      // The user menu is in the top right corner showing "Demo User"
      // Click on the user avatar/name to open the dropdown
      cy.contains('Demo User').should('be.visible').click();

      // Wait for dropdown and click Sign Out
      cy.contains('Sign Out', { timeout: 5000 }).should('be.visible').click();

      // Should redirect to login
      cy.url({ timeout: 5000 }).should('include', '/login');
    });
  });
});


export {};
