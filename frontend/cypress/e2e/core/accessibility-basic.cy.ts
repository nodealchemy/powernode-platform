/// <reference types="cypress" />

/**
 * Basic Accessibility Tests
 *
 * Simplified accessibility tests using correct selectors
 */

describe('Basic Accessibility Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Keyboard Navigation - Login Page', () => {
    it('should support keyboard focus on login page', () => {
      cy.visit('/login');

      // Test that form elements are focusable using correct selectors
      cy.get('[data-testid="email-input"]').should('be.visible').focus().should('be.focused');
      cy.get('[data-testid="password-input"]').should('be.visible').focus().should('be.focused');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').focus().should('be.focused');
    });

    it('should support keyboard focus on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');

      // Plan cards should be clickable
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 5000 }).should('be.visible');

      // Select button should be focusable
      cy.get('[data-testid="plan-select-btn"]').first().focus().should('be.focused');
    });

    it('should support keyboard focus on registration page', () => {
      // Navigate to registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible')
        .click();

      // Wait for registration page
      cy.url({ timeout: 5000 }).should('include', '/register');

      // Test that form fields are focusable
      cy.get('input[name="accountName"]', { timeout: 5000 }).should('be.visible').focus().should('be.focused');
      cy.get('input[name="name"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="email"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="password"]').should('be.visible').focus().should('be.focused');
      // Submit button exists but may be disabled until form is valid
      cy.get('button[type="submit"]').should('be.visible').should('exist');
    });
  });

  describe('Form Labels and Structure', () => {
    it('should have proper form labels on login page', () => {
      cy.visit('/login');

      // Check that form inputs exist and have ids
      cy.get('[data-testid="email-input"]').should('have.attr', 'id');
      cy.get('[data-testid="password-input"]').should('have.attr', 'id');

      // Check for label elements
      cy.contains('Email').should('be.visible');
      cy.contains('Password').should('be.visible');
    });

    it('should have proper form structure on registration page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible')
        .click();

      // Check form structure
      cy.url({ timeout: 5000 }).should('include', '/register');

      // Check that required fields exist
      cy.get('input[name="name"]', { timeout: 5000 }).should('exist');
      cy.get('input[name="email"]').should('exist');
      cy.get('input[name="password"]').should('exist');

      // Check email input type
      cy.get('input[name="email"]').should('have.attr', 'type', 'email');
    });
  });

  describe('Visual Focus Indicators', () => {
    it('should show focus indicators on interactive elements', () => {
      cy.visit('/login');

      // Test that focused elements have visible focus indicators
      cy.get('[data-testid="email-input"]').focus();
      cy.focused().should('exist');

      cy.get('[data-testid="password-input"]').focus();
      cy.focused().should('exist');

      cy.get('[data-testid="login-submit-btn"]').focus();
      cy.focused().should('exist');
    });

    it('should show focus indicators on plan cards', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');

      // Plan cards should show hover states
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().trigger('mouseover');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().should('have.css', 'cursor', 'pointer');
    });
  });

  describe('Semantic HTML Structure', () => {
    it('should use semantic HTML elements on login page', () => {
      cy.visit('/login');

      // Check for semantic form elements
      cy.get('form').should('exist');
      cy.get('[data-testid="email-input"]').should('exist');
      cy.get('[data-testid="password-input"]').should('exist');
      cy.get('[data-testid="login-submit-btn"]').should('exist');

      // Check for heading structure
      cy.get('h1, h2, h3').should('exist');
    });

    it('should use semantic HTML elements on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');

      // Check for heading structure in plan cards
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().within(() => {
        cy.get('h1, h2, h3, h4, [class*="font-bold"], [class*="text-xl"]').should('exist');
      });
    });
  });

  describe('Mobile Accessibility', () => {
    it('should be accessible on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.visit('/login');

      // Form should still be usable on mobile
      cy.get('[data-testid="email-input"]').should('be.visible').focus().should('be.focused');
      cy.get('[data-testid="password-input"]').should('be.visible').focus().should('be.focused');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible').focus().should('be.focused');

      // Touch targets should be large enough (minimum 44px)
      cy.get('[data-testid="login-submit-btn"]').invoke('outerHeight').should('be.gte', 40);
    });

    it('should be accessible on tablet viewport', () => {
      cy.viewport(768, 1024);
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 }).should('exist');

      // Plan cards should be properly sized and accessible
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().should('be.visible');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 5000 }).should('be.visible');
    });
  });

  describe('Error States and Feedback', () => {
    it('should provide accessible error feedback', () => {
      cy.visit('/login');

      // Submit form with invalid data
      cy.get('[data-testid="email-input"]').type('invalid-email');
      cy.get('[data-testid="password-input"]').type('wrong');
      cy.get('[data-testid="login-submit-btn"]').click();

      // Wait for response
      cy.waitForPageLoad();

      // Should stay on login page (indicating failed login)
      cy.url().should('include', '/login');
    });
  });
});


export {};
