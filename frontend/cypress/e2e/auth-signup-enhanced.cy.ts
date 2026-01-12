describe('Enhanced Authentication & Sign-up Flow Tests', () => {
  const timestamp = Date.now();

  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Sign-up Flow - Complete Registration Process', () => {
    it('should complete the entire sign-up journey from landing to dashboard', () => {
      const userData = {
        email: `signup-complete-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        name: 'SignUp Complete',
        accountName: 'SignUp Complete Co'
      };

      // Step 1: Start from homepage/landing
      cy.visit('/');

      // Navigate to sign-up (via plans page)
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');

      // Step 2: Plan selection
      cy.get('[data-testid="plan-card"]').first().click({ force: true });
      cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').click({ force: true });

      // Step 3: Registration form
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');

      // Fill out complete registration form using data-testid selectors
      cy.get('[data-testid="account-name-input"]').type(userData.accountName);
      cy.get('[data-testid="name-input"]').type(userData.name);
      cy.get('[data-testid="register-email-input"]').type(userData.email);
      cy.get('[data-testid="register-password-input"]').type(userData.password);

      // Verify form is ready for submission
      cy.get('[data-testid="register-submit-btn"]').should('not.be.disabled');

      // Step 4: Submit registration
      cy.get('[data-testid="register-submit-btn"]').click();

      // Step 5: Verify successful registration - redirects to app, dashboard, or verify-email
      cy.url({ timeout: 20000 }).should('match', /\/(app|dashboard|verify-email)/);
    });

    it('should handle sign-up with different plan selections', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');

      // Test different plan selection if multiple plans available
      cy.get('[data-testid="plan-card"]').then($cards => {
        if ($cards.length > 1) {
          // Select second plan
          cy.get('[data-testid="plan-card"]').eq(1).click({ force: true });
          cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).should('be.visible');
          cy.get('[data-testid="continue-to-registration"]').click({ force: true });

          // Verify plan is selected
          cy.url().should('include', '/register');
          cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');

          // Complete registration with different plan
          const userData = {
            email: `plan2-signup-${timestamp}-${Math.random()}@example.com`,
            password: 'Qx7#mK9@pL2$nZ6%',
            name: 'Plan2 User',
            accountName: 'Plan2 User Co'
          };

          cy.get('[data-testid="account-name-input"]').type(userData.accountName);
          cy.get('[data-testid="name-input"]').type(userData.name);
          cy.get('[data-testid="register-email-input"]').type(userData.email);
          cy.get('[data-testid="register-password-input"]').type(userData.password);

          cy.get('[data-testid="register-submit-btn"]').should('not.be.disabled');
          cy.get('[data-testid="register-submit-btn"]').click();

          cy.url({ timeout: 20000 }).should('match', /\/(app|dashboard|verify-email)/);
        } else {
          cy.log('Only one plan available - skipping multi-plan test');
        }
      });
    });

    it('should validate sign-up form with comprehensive field validation', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click({ force: true });
      cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').click({ force: true });

      // Wait for registration form
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');

      // Test empty form validation - submit button should be disabled
      cy.get('[data-testid="register-submit-btn"]').should('be.disabled');
    });
  });

  describe('Enhanced Login Flow Testing', () => {
    it('should handle successful login with enhanced validation', () => {
      // Use seeded demo user
      cy.visit('/login');

      // Verify login form is properly loaded using actual data-testid selectors
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible').and('not.be.disabled');
      cy.get('[data-testid="password-input"]').should('be.visible').and('not.be.disabled');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible');

      // Test form interaction using actual data-testid selectors
      cy.get('[data-testid="email-input"]').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');

      // Verify form state before submission
      cy.get('[data-testid="email-input"]').should('have.value', 'demo@democompany.com');

      // Submit login using actual selector
      cy.get('[data-testid="login-submit-btn"]').click();

      // Verify successful login
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    });

    it('should handle login errors with proper feedback', () => {
      cy.visit('/login');

      // Wait for login page to fully load
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible');

      // Fill email field
      cy.get('[data-testid="email-input"]').clear().type('demo@democompany.com');

      // Fill password field with wrong password
      cy.get('[data-testid="password-input"]').clear().type('wrongpassword123');

      // Submit form
      cy.get('[data-testid="login-submit-btn"]').click();

      // Wait for authentication attempt
      cy.wait(3000);

      // Should stay on login page
      cy.url().should('include', '/login');
    });

    it('should handle non-existent user login attempts', () => {
      cy.visit('/login');

      cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible');

      // Test with non-existent email
      cy.get('[data-testid="email-input"]').clear().type('nonexistent-user-123456@example.com');
      cy.get('[data-testid="password-input"]').clear().type('Qx7#mK9@pL2$nZ6%');

      // Submit login attempt
      cy.get('[data-testid="login-submit-btn"]').click();

      // Wait for authentication response
      cy.wait(3000);

      // Should stay on login page
      cy.url().should('include', '/login');
    });

    it('should maintain form state during validation errors', () => {
      cy.visit('/login');

      const testEmail = 'maintain-state@example.com';

      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type(testEmail);
      cy.get('[data-testid="password-input"]').type('wrongpassword');
      cy.get('[data-testid="login-submit-btn"]').click();

      cy.wait(2000);

      // Email should be maintained (good UX)
      cy.get('[data-testid="email-input"]').should('have.value', testEmail);

      // Form should be ready for retry
      cy.get('[data-testid="password-input"]').should('be.enabled');
      cy.get('[data-testid="login-submit-btn"]').should('be.enabled');
    });

    it('should handle login form accessibility features', () => {
      cy.visit('/login');

      // Wait for form to load
      cy.get('[data-testid="email-input"]', { timeout: 15000 }).should('be.visible');

      // Test elements are focusable
      cy.get('[data-testid="email-input"]').focus().should('be.focused');
      cy.get('[data-testid="password-input"]').focus().should('be.focused');

      // Test password field type
      cy.get('[data-testid="password-input"]').should('have.attr', 'type', 'password');
    });
  });

  describe('Password Security & Validation', () => {
    it('should enforce password strength requirements', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click({ force: true });
      cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').click({ force: true });

      // Wait for registration form
      cy.url().should('include', '/register');
      cy.get('[data-testid="account-name-input"]').should('be.visible');

      // Fill required fields first
      cy.get('[data-testid="account-name-input"]').type('Password Test Co');
      cy.get('[data-testid="name-input"]').type('Password Test');
      cy.get('[data-testid="register-email-input"]').type(`password-test-${timestamp}@example.com`);

      // Test weak password - should keep submit disabled
      cy.get('[data-testid="register-password-input"]').type('short');
      cy.get('[data-testid="register-submit-btn"]').should('be.disabled');

      // Test strong password - should enable form submission
      cy.get('[data-testid="register-password-input"]').clear().type('Qx7#mK9@pL2$nZ6%');
      cy.get('[data-testid="register-submit-btn"]').should('not.be.disabled');
    });
  });

  describe('Email Verification Flow', () => {
    it('should handle post-registration email verification if required', () => {
      const userData = {
        email: `email-verify-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        name: 'EmailVerify User',
        accountName: 'Email Verify Co'
      };

      // Complete registration
      cy.register(userData);

      // Check result - should be on app, dashboard, or verify-email page
      cy.url().should('match', /\/(app|dashboard|verify-email)/);
    });
  });

  describe('Authentication Error Recovery', () => {
    it('should handle network failures during registration gracefully', () => {
      // Simulate network failure
      cy.intercept('POST', '/api/v1/auth/register', { forceNetworkError: true }).as('networkFailure');

      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click({ force: true });
      cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').click({ force: true });

      const userData = {
        email: `network-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        name: 'Network Test',
        accountName: 'Network Test Co'
      };

      cy.get('[data-testid="account-name-input"]').type(userData.accountName);
      cy.get('[data-testid="name-input"]').type(userData.name);
      cy.get('[data-testid="register-email-input"]').type(userData.email);
      cy.get('[data-testid="register-password-input"]').type(userData.password);

      cy.get('[data-testid="register-submit-btn"]').click();

      // Wait for network error
      cy.wait('@networkFailure');
      cy.wait(2000);

      // Should stay on register page
      cy.url().should('include', '/register');

      // Form should remain usable
      cy.get('[data-testid="register-email-input"]').should('have.value', userData.email);
      cy.get('[data-testid="register-submit-btn"]').should('be.enabled');
    });

    it('should handle session timeout and re-authentication', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').click();

      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);

      // Simulate session expiry by clearing local storage
      cy.clearLocalStorage();

      // Try to access protected route
      cy.visit('/app');

      // Should redirect to login
      cy.url().should('include', '/login');

      // Should be able to log back in
      cy.get('[data-testid="email-input"]').type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').click();

      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    });
  });

  describe('Social Login Integration', () => {
    it('should display social login options if available', () => {
      cy.visit('/login');

      // Check for social login buttons
      const socialProviders = [
        '[data-testid="google-login"]',
        '[data-testid="github-login"]',
        '.social-login'
      ];

      socialProviders.forEach(selector => {
        cy.get('body').then($body => {
          if ($body.find(selector).length > 0) {
            cy.log(`Social login found: ${selector}`);
            cy.get(selector).should('be.visible');
          }
        });
      });
    });
  });

  describe('Remember Me & Session Persistence', () => {
    it('should handle session persistence', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');

      // Check remember me if available
      cy.get('body').then($body => {
        if ($body.find('input[type="checkbox"]').length > 0) {
          cy.get('input[type="checkbox"]').first().check({ force: true });
        }
      });

      cy.get('[data-testid="login-submit-btn"]').click();

      // Wait for login to complete
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);

      // Test session persistence with page reload
      cy.reload();

      // Should still be logged in after reload
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });
});
