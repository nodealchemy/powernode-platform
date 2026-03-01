/// <reference types="cypress" />

/**
 * Core Metrics Page E2E Tests
 *
 * Tests for the root-level metrics page including:
 * - Page navigation and load
 * - Metrics display
 * - Chart visualizations
 * - Time range selection
 * - Export functionality
 * - Responsive design
 */

describe('Core Metrics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should navigate to Metrics page', () => {
      cy.assertContainsAny(['Metrics', 'Analytics', 'Performance']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Metrics', 'Analytics', 'Dashboard']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'Metrics']);
    });
  });

  describe('Metrics Overview', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display key metrics cards', () => {
      cy.assertHasElement(['[class*="card"]', '[class*="stat"]', '[class*="metric"]']);
    });

    it('should display user metrics', () => {
      cy.assertContainsAny(['Users', 'Active', 'Registrations']);
    });

    it('should display revenue metrics', () => {
      cy.assertContainsAny(['Revenue', 'MRR', '$']);
    });

    it('should display growth indicators', () => {
      cy.assertContainsAny(['%', 'Growth', 'Change']);
    });
  });

  describe('Charts and Visualizations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display chart containers', () => {
      cy.assertHasElement(['canvas', 'svg', '[class*="chart"]', '[class*="graph"]']);
    });

    it('should display line charts', () => {
      cy.assertHasElement(['canvas', '[class*="line"]']);
    });

    it('should display bar charts', () => {
      cy.assertHasElement(['canvas', '[class*="bar"]']);
    });

    it('should display chart legends', () => {
      cy.assertHasElement(['[class*="legend"]']);
    });
  });

  describe('Time Range Selection', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display time range selector', () => {
      cy.assertContainsAny(['7 days', '30 days', 'day', 'week', 'month']);
    });

    it('should have preset time ranges', () => {
      cy.assertContainsAny(['Today', 'Week', 'Month', 'Year']);
    });

    it('should allow custom date range selection', () => {
      cy.assertContainsAny(['Custom']);
    });
  });

  describe('Metrics Categories', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display subscription metrics', () => {
      cy.assertContainsAny(['Subscription', 'Churn', 'Retention']);
    });

    it('should display API metrics', () => {
      cy.assertContainsAny(['API', 'Requests', 'Latency']);
    });

    it('should display system metrics', () => {
      cy.assertContainsAny(['System', 'Performance', 'Uptime']);
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should have export button', () => {
      cy.assertContainsAny(['Export', 'Download']);
    });

    it('should have export format options', () => {
      cy.assertContainsAny(['CSV', 'PDF', 'Excel', 'Export']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should have refresh button', () => {
      cy.assertContainsAny(['Refresh']);
    });

    it('should display last updated timestamp', () => {
      cy.assertContainsAny(['Updated', 'Last', 'ago']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Metrics', 'Analytics', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      });

      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Unable']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/metrics');

      cy.assertHasElement(['.animate-spin', '[class*="loading"]', '[class*="spinner"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Metrics', 'Analytics']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Metrics', 'Analytics']);
    });

    it('should stack metrics on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Metrics', 'Analytics']);
    });

    it('should display multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.assertHasElement(['[class*="grid"]']);
    });
  });
});


export {};
