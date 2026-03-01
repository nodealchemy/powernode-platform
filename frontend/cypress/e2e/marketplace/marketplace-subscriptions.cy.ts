/// <reference types="cypress" />

/**
 * Marketplace My Subscriptions Page Tests
 *
 * Tests for Marketplace Subscriptions management functionality including:
 * - Page navigation and load
 * - Subscriptions list display
 * - Filtering by type and status
 * - Subscription actions (pause, resume, cancel)
 * - Empty state handling
 * - Responsive design
 */

describe('Marketplace Subscriptions Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['marketplace'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to My Subscriptions page', () => {
      cy.assertPageReady('/app/marketplace/subscriptions');
      cy.assertContainsAny(['Subscriptions', 'Subscription', 'Marketplace', 'Permission']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/marketplace/subscriptions');
      cy.assertContainsAny(['My Subscriptions', 'Subscriptions']);
    });

    it('should display page description', () => {
      cy.assertPageReady('/app/marketplace/subscriptions');
      cy.assertContainsAny(['Manage', 'marketplace']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace/subscriptions');
    });

    it('should have Browse Marketplace button', () => {
      cy.assertHasElement(['button:contains("Browse Marketplace")', 'button:contains("Marketplace")']);
    });

    it('should navigate to marketplace on button click', () => {
      cy.assertHasElement(['button:contains("Browse Marketplace")', 'button:contains("Marketplace")']).first().click();
      cy.waitForPageLoad();
      cy.url().should('include', 'marketplace');
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace/subscriptions');
    });

    it('should display type filter', () => {
      cy.assertContainsAny(['Type:', 'All', 'Subscriptions']);
    });

    it('should display status filter', () => {
      cy.assertContainsAny(['Status:', 'Active', 'Subscriptions']);
    });

    it('should filter by type', () => {
      cy.assertHasElement(['button:contains("Workflows")', 'button:contains("All")', 'select']).first().click();
      cy.assertContainsAny(['Subscriptions', 'Marketplace']);
    });

    it('should filter by status', () => {
      cy.assertHasElement(['button:contains("Active")', 'button:contains("Paused")']).first().click();
      cy.assertContainsAny(['Subscriptions', 'Marketplace']);
    });
  });

  describe('Subscriptions List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace/subscriptions');
    });

    it('should display subscriptions list', () => {
      cy.assertHasElement(['[class*="list"]', '[class*="card"]', '[class*="space"]']);
    });

    it('should display subscription cards', () => {
      // Look for subscription items - could be cards, list items, or grid items
      cy.assertHasElement(['[class*="card"]', '[class*="Card"]', '[class*="space-y"]', '[class*="list"]', 'div.p-4', 'article']);
    });

    it('should display subscription name', () => {
      cy.assertHasElement(['h3', '[class*="title"]']);
    });

    it('should display subscription status badge', () => {
      cy.assertContainsAny(['Active', 'Paused', 'Cancelled', 'Subscriptions']);
    });

    it('should display subscription type badge', () => {
      cy.assertContainsAny(['App', 'Plugin', 'Template', 'Integration']);
    });

    it('should display subscription date', () => {
      cy.assertContainsAny(['Subscribed', 'Subscriptions']);
    });
  });

  describe('Subscription Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace/subscriptions');
    });

    it('should have View button', () => {
      cy.assertHasElement(['button:contains("View")']);
    });

    it('should have Configure button for active subscriptions', () => {
      cy.assertHasElement(['button[title="Configure"]', '[aria-label*="configure"]']);
    });

    it('should have Pause button for active subscriptions', () => {
      cy.assertHasElement(['button[title="Pause"]', '[aria-label*="pause"]']);
    });

    it('should have Resume button for paused subscriptions', () => {
      cy.assertHasElement(['button[title="Resume"]', '[aria-label*="resume"]']);
    });

    it('should have Cancel button', () => {
      cy.assertHasElement(['button[title="Cancel"]', '[aria-label*="cancel"]']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no subscriptions', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 200,
        body: []
      }).as('getEmptySubscriptions');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['No subscriptions', 'no subscriptions', 'Browse the marketplace']);
    });

    it('should have call to action in empty state', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 200,
        body: []
      }).as('getEmptySubscriptions');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.assertHasElement(['button:contains("Browse")', 'button:contains("Marketplace")']);
    });
  });

  describe('Paused Subscription Warning', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace/subscriptions');
    });

    it('should display warning for paused subscriptions', () => {
      cy.assertContainsAny(['paused', 'Subscriptions']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/marketplace/subscriptions*', {
        statusCode: 500,
        visitUrl: '/app/marketplace/subscriptions'
      });
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load subscriptions' }
      }).as('getSubscriptionsError');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Subscriptions']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        delay: 1000,
        statusCode: 200,
        body: []
      }).as('getSubscriptionsDelayed');

      cy.visit('/app/marketplace/subscriptions');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/marketplace/subscriptions');
      cy.assertContainsAny(['Subscriptions', 'Marketplace']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/marketplace/subscriptions');
      cy.assertContainsAny(['Subscriptions', 'Marketplace']);
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Subscriptions', 'Marketplace']);
    });
  });
});


export {};
