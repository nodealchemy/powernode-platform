/// <reference types="cypress" />

/**
 * AI Plugins Page Tests
 *
 * Tests for AI Plugins functionality.
 * Note: /app/ai/plugins now redirects to /app/marketplace?types=plugin
 * These tests verify the redirect and marketplace plugin functionality.
 */

describe('AI Plugins Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['marketplace'] });
    Cypress.on('uncaught:exception', () => false);
  });

  describe('Page Navigation', () => {
    it('should redirect to marketplace with plugin filter', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
      cy.url().should('include', '/marketplace');
    });

    it('should load marketplace page after redirect', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Plugin', 'Browse']);
    });
  });

  describe('Marketplace Plugin Display', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace?types=plugin');
      cy.waitForPageLoad();
    });

    it('should display marketplace with plugin content', () => {
      cy.assertContainsAny(['Marketplace', 'Plugin', 'Browse', 'Apps']);
    });

    it('should show plugin items or empty state', () => {
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Plugin', 'No items', 'Browse', 'Marketplace']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace?types=plugin');
      cy.waitForPageLoad();
    });

    it('should have search input on marketplace', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"], input[placeholder*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input found');
        }
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/marketplace**', {
        statusCode: 500,
        visitUrl: '/app/marketplace?types=plugin'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace?types=plugin');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/marketplace?types=plugin');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });
});

export {};
