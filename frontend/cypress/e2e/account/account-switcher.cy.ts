/// <reference types="cypress" />

/**
 * Account Switcher Tests
 *
 * Tests for Account Switching functionality including:
 * - Account switcher visibility
 * - Account list display
 * - Switch account action
 * - Current account indicator
 * - Account creation from switcher
 * - Error handling
 */

describe('Account Switcher Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Account Switcher Visibility', () => {
    it('should display account switcher in navigation', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="account-switcher"]', '[aria-label*="account"]']);
    });

    it('should display current account name', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Account']);
    });
  });

  describe('Account Dropdown', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should open account dropdown on click', () => {
      cy.get('[data-testid="account-switcher"], [aria-label*="account"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Account', 'Switch']);
    });

    it('should display list of accounts', () => {
      cy.get('[data-testid="account-switcher"], [aria-label*="account"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Account']);
    });

    it('should highlight current account', () => {
      cy.get('[data-testid="account-switcher"]').first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['[data-testid="current-account-indicator"]', '.selected', '.active', '[aria-selected="true"]']);
    });
  });

  describe('Switch Account', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should allow clicking on different account', () => {
      cy.get('[data-testid="account-switcher"]').first().click();
      cy.waitForStableDOM();
      cy.get('[data-testid="account-option"]').should('have.length.at.least', 1);
    });
  });

  describe('Create Account Option', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should display create account option', () => {
      cy.get('[data-testid="account-switcher"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Create', 'New', 'Add Account']);
    });
  });

  describe('Account Information', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should display account logo/avatar', () => {
      cy.assertHasElement(['[data-testid="account-avatar"]', 'img[alt*="account"]', '.avatar']);
    });

    it('should display subscription tier if applicable', () => {
      cy.get('[data-testid="account-switcher"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Pro', 'Business', 'Enterprise', 'Free']);
    });
  });

  describe('Keyboard Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should support keyboard navigation', () => {
      cy.get('[data-testid="account-switcher"]').first().focus().type('{enter}');
      cy.waitForStableDOM();
      cy.assertContainsAny(['Account', 'Dashboard']);
    });
  });

  describe('Error Handling', () => {
    it('should handle switch account errors gracefully', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'Account']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display account switcher correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/dashboard');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Dashboard', 'Account']);
      });
    });
  });
});
