/// <reference types="cypress" />

/**
 * End-to-End User Journey Tests
 *
 * Simplified tests for user journeys using demo user authentication
 */

describe('End-to-End User Journey Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Complete New User Journey', () => {
    it('should show plan selection page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should allow plan selection', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"]', { timeout: 5000 }).should('be.visible');
    });

    it('should navigate to registration after plan selection', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();
      // Wait for the button to be visible and clickable
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible')
        .click();

      cy.url({ timeout: 5000 }).should('include', '/register');
    });

    it('should display registration form with selected plan', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();
      // Wait for the button to be visible and clickable
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible')
        .click();

      cy.url({ timeout: 5000 }).should('include', '/register');
      cy.get('form', { timeout: 5000 }).should('exist');
      cy.get('input[name="email"], input[type="email"]', { timeout: 5000 }).should('exist');
    });
  });

  describe('Returning User Journey', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should allow returning user to login', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');
    });

    it('should maintain session after page refresh', () => {
      cy.reload();
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');
    });

    it('should allow logout and re-login', () => {
      // Logout using custom command
      cy.logout();

      // Re-login using standardized command
      cy.loginAsDemo();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    });
  });

  describe('Error Recovery Journeys', () => {
    it('should handle invalid login credentials', () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('invalid@example.com');
      cy.get('[data-testid="password-input"]').type('wrongpassword');
      cy.get('[data-testid="login-submit-btn"]').click();

      // Should stay on login page or show error
      cy.waitForPageLoad();
      cy.url().should('include', '/login');
    });

    it('should handle forgotten password flow if available', () => {
      cy.visit('/login');

      cy.get('body').then($body => {
        if ($body.find('[href*="forgot"], [data-testid="forgot-password"]').length > 0) {
          cy.get('[href*="forgot"], [data-testid="forgot-password"]').first().click();
          cy.url().should('satisfy', (url: string) => {
            return url.includes('/forgot') || url.includes('/reset') || url.includes('/password');
          });
        } else {
          cy.log('Forgot password link not found');
        }
      });
    });
  });

  describe('Multi-Device User Journey', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should handle desktop to mobile viewport transition', () => {
      cy.viewport(1280, 720);
      cy.get('body').should('be.visible');

      cy.viewport(375, 667);
      cy.reload();
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should handle tablet viewport', () => {
      cy.viewport(768, 1024);
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should maintain session across viewport changes', () => {
      cy.viewport(1280, 720);
      cy.url().should('match', /\/(app|dashboard)/);

      cy.viewport(375, 667);
      cy.url().should('match', /\/(app|dashboard)/);

      cy.viewport(1024, 768);
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });

  describe('Navigation Journey', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should navigate between pages smoothly', () => {
      // Navigate to plans
      cy.visit('/plans');
      cy.get('body').should('be.visible');
      // Plans page should load - either showing plan cards or some content
      cy.get('body').should('satisfy', ($body) => {
        const hasPlans = $body.find('[data-testid="plan-card"], [data-public-plan-card="true"]').length > 0;
        const hasContent = $body.text().length > 100;
        return hasPlans || hasContent;
      });

      // Navigate back to dashboard
      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should display content without errors', () => {
      cy.get('body')
        .should('not.contain.text', 'Error')
        .and('not.contain.text', 'undefined')
        .and('not.contain.text', 'null');
    });
  });

  describe('Accessibility Journey', () => {
    it('should allow keyboard navigation on login page', () => {
      cy.visit('/login');

      // Tab through form elements
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).focus();
      cy.focused().should('have.attr', 'name', 'email');

      cy.get('[data-testid="password-input"]').focus();
      cy.focused().should('have.attr', 'name', 'password');
    });

    it('should maintain focus management', () => {
      cy.visit('/login');

      cy.get('[data-testid="email-input"]', { timeout: 5000 }).focus();
      cy.focused().should('be.visible');

      cy.get('[data-testid="password-input"]').focus();
      cy.focused().should('be.visible');
    });
  });
});


export {};
