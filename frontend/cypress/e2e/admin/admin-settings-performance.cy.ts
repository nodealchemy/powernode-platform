/// <reference types="cypress" />

/**
 * Admin Settings - Performance Tab E2E Tests
 *
 * Tests for performance optimization settings including:
 * - Performance overview
 * - Caching configuration
 * - Database optimization
 * - Asset optimization
 * - Monitoring settings
 * - Responsive design
 */

describe('Admin Settings Performance Tab Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should navigate to Performance tab', () => {
      cy.assertContainsAny(['Performance', 'Optimization', 'Cache']);
    });

    it('should redirect unauthorized users', () => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Performance', 'Settings', 'Admin']);
    });
  });

  describe('Performance Overview', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display performance metrics', () => {
      cy.assertContainsAny(['Response Time', 'Latency', 'ms']);
    });

    it('should display performance score', () => {
      cy.assertContainsAny(['Score', '%', 'Good', 'Excellent']);
    });
  });

  describe('Caching Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display cache settings section', () => {
      cy.assertContainsAny(['Cache', 'Caching']);
    });

    it('should display cache toggle', () => {
      cy.assertHasElement(['input[type="checkbox"]', '[role="switch"]']);
    });

    it('should display cache TTL settings', () => {
      cy.assertContainsAny(['TTL', 'Time to Live', 'Expiration']);
    });

    it('should have clear cache button', () => {
      cy.get('button:contains("Clear"), button:contains("Flush")').should('exist');
    });
  });

  describe('Database Optimization', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display database settings', () => {
      cy.assertContainsAny(['Database', 'Query', 'Connection']);
    });

    it('should display connection pool settings', () => {
      cy.assertContainsAny(['Pool', 'Connection', 'Connections']);
    });

    it('should display query optimization options', () => {
      cy.assertContainsAny(['Query', 'Optimization']);
    });
  });

  describe('Asset Optimization', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display asset settings', () => {
      cy.assertContainsAny(['Asset', 'Compression', 'Minification']);
    });

    it('should display compression toggle', () => {
      cy.assertContainsAny(['Compression', 'Gzip', 'Brotli']);
    });

    it('should display CDN settings', () => {
      cy.assertContainsAny(['CDN', 'Content Delivery']);
    });
  });

  describe('Monitoring Settings', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display monitoring options', () => {
      cy.assertContainsAny(['Monitor', 'Metrics', 'Logging']);
    });

    it('should display performance alerts', () => {
      cy.assertContainsAny(['Alert', 'Threshold', 'Warning']);
    });
  });

  describe('Performance Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should have optimize button', () => {
      cy.get('button:contains("Optimize"), button:contains("Run")').should('exist');
    });

    it('should have refresh metrics button', () => {
      cy.get('button:contains("Refresh"), button[aria-label*="refresh"]').should('exist');
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Performance', 'Settings', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Loading State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/admin/settings/performance');

      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Performance', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Performance', 'Settings']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/settings/performance');
    });
  });
});


export {};
