/// <reference types="cypress" />

/**
 * Logo Navigation - Simple Tests
 *
 * Simplified navigation tests using demo user
 */

describe('Logo Navigation - Simple Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should display login form on login page', () => {
    cy.visit('/login');

    // Check for login form elements
    cy.get('[data-testid="email-input"]').should('be.visible');
    cy.get('[data-testid="password-input"]').should('be.visible');
    cy.get('[data-testid="login-submit-btn"]').should('be.visible');
  });

  it('should navigate to dashboard after login', () => {
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

    // Check navigation exists
    cy.get('nav, aside, [role="navigation"]').should('exist');
  });
});


export {};
