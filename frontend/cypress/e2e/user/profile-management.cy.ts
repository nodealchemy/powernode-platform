/// <reference types="cypress" />

/**
 * Profile Management E2E Tests
 *
 * Tests for user profile display and management
 */

describe('Profile Management', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Profile Display', () => {
    it('should navigate to profile/settings page', () => {
      cy.navigateTo('settings');
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display user information', () => {
      cy.contains('Demo', { timeout: 5000 }).should('exist');
    });
  });

  describe('User Menu', () => {
    it('should open user menu dropdown', () => {
      cy.contains('Demo User').should('be.visible').click();
      cy.get('body').should('contain.text', 'Sign Out');
    });

    it('should navigate to profile from user menu', () => {
      cy.contains('Demo User').should('be.visible').click();
      cy.assertHasElement(['a[href*="profile"]', '[data-testid="profile-link"]']);
    });
  });

  describe('Session Management', () => {
    it('should logout successfully', () => {
      cy.contains('Demo User').should('be.visible').click();
      cy.contains('Sign Out').should('be.visible').click();
      cy.url({ timeout: 5000 }).should('include', '/login');
    });

    it('should maintain session across page refresh', () => {
      cy.reload();
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
      cy.contains('Demo', { timeout: 5000 }).should('exist');
    });
  });
});


export {};
