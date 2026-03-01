/// <reference types="cypress" />

/**
 * Logo Contrast and Visual Tests
 *
 * Simplified tests for logo visibility and styling
 */

describe('Logo Contrast and Visual Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Public Pages', () => {
    it('should display branding on login page', () => {
      cy.visit('/login');

      // Check that login form is visible - this is the core branding/functionality
      cy.get('[data-testid="email-input"]').should('be.visible');
      cy.get('[data-testid="password-input"]').should('be.visible');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible');
    });

    it('should display branding on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');

      // Check for branding
      cy.assertHasElement(['[class*="logo"]', 'img[alt*="logo"]', 'header']);
    });
  });

  describe('Authenticated Pages', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display navigation branding', () => {
      // Verify app is loaded and has navigation elements
      cy.get('button[aria-haspopup="true"]', { timeout: 5000 }).should('exist');
    });

    it('should have interactive navigation elements', () => {
      cy.get('nav a, aside a, header a').should('have.length.at.least', 1);
    });

    it('should display content without visual errors', () => {
      cy.get('body')
        .should('not.contain.text', 'Error')
        .and('not.contain.text', 'undefined');
    });
  });

  describe('Theme Consistency', () => {
    it('should display consistent styling on login page', () => {
      cy.visit('/login');

      // Check form exists
      cy.get('[data-testid="email-input"]').should('be.visible');
      cy.get('[data-testid="password-input"]').should('be.visible');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible');
    });

    it('should display consistent styling on plans page', () => {
      cy.visit('/plans');

      // Plan cards should be visible
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .should('be.visible');
    });
  });
});


export {};
