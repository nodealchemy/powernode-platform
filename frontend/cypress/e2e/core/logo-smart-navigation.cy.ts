/// <reference types="cypress" />

/**
 * Logo Smart Navigation Tests
 *
 * Simplified smart navigation tests using demo user
 */

describe('Logo Smart Navigation', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Public Navigation', () => {
    it('should display form on login page', () => {
      cy.visit('/login');

      // Check for login form elements
      cy.get('[data-testid="email-input"]').should('be.visible');
      cy.get('[data-testid="password-input"]').should('be.visible');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible');
    });

    it('should allow navigation to plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });
  });

  describe('Authenticated Navigation', () => {
    beforeEach(() => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    });

    it('should display navigation sidebar/header', () => {
      cy.get('nav, aside, header, [role="navigation"]').should('exist');
    });

    it('should have navigation links', () => {
      cy.get('nav a, aside a, [role="navigation"] a').should('have.length.at.least', 1);
    });

    it('should navigate between pages', () => {
      // Navigate to settings
      cy.visit('/app/settings/profile');
      cy.get('body').should('be.visible');

      // Navigate back to app
      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should maintain session during navigation', () => {
      // Navigate to different pages
      cy.visit('/app/settings/profile');
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);

      // User should still be logged in
      cy.get('button[aria-haspopup="true"]', { timeout: 10000 }).should('be.visible');
    });
  });
});
