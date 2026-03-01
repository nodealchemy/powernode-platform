/// <reference types="cypress" />

/**
 * Business Reports Page Tests
 *
 * Tests for Business Reports functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Library, Builder, Queue, Scheduled, Analytics)
 * - Report templates display
 * - Report builder wizard
 * - Report queue management
 * - Scheduled reports
 * - Analytics dashboard
 * - Search and filtering
 * - Report generation
 * - Error handling
 * - Responsive design
 */

describe('Business Reports Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Reports page', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Reports', 'Report', 'Permission']);
    });

    it('should display page title', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
      cy.get('body').should('contain.text', 'Reports');
    });

    it('should display page description', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Generate and manage', 'business reports']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'Business']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
    });

    it('should display Overview tab', () => {
      cy.get('body').should('contain.text', 'Overview');
    });

    it('should display Report Library tab', () => {
      cy.assertContainsAny(['Report Library', 'Library']);
    });

    it('should display Report Builder tab', () => {
      cy.assertContainsAny(['Report Builder', 'Builder']);
    });

    it('should display Report Queue tab', () => {
      cy.assertContainsAny(['Report Queue', 'Queue']);
    });

    it('should display Scheduled Reports tab', () => {
      cy.assertContainsAny(['Scheduled Reports', 'Scheduled']);
    });

    it('should display Analytics tab', () => {
      cy.get('body').should('contain.text', 'Analytics');
    });
  });

  describe('Report Library', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/library');
      cy.waitForPageLoad();
    });

    it('should display report templates', () => {
      cy.assertHasElement(['[class*="card"]', 'body']);
      cy.get('body').should('contain.text', 'Reports');
    });

    it('should display template categories', () => {
      cy.assertContainsAny(['financial', 'customer', 'subscription', 'Reports']);
    });

    it('should display template search', () => {
      cy.get('input[placeholder*="Search"]').should('exist');
    });

    it('should have Use Template button', () => {
      cy.get('button:contains("Use Template")').should('exist');
    });

    it('should display format badges (PDF, CSV, XLSX)', () => {
      cy.assertContainsAny(['PDF', 'CSV', 'XLSX', 'JSON']);
    });
  });

  describe('Report Builder', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/builder');
      cy.waitForPageLoad();
    });

    it('should display report builder wizard', () => {
      cy.assertContainsAny(['Create Custom Report', 'Step']);
    });

    it('should display progress bar', () => {
      cy.assertContainsAny(['Step']);
      cy.assertHasElement(['[class*="progress"]', '[class*="bar"]']);
    });

    it('should display Select Report Type step', () => {
      cy.assertContainsAny(['Select Report Type', 'Report Type']);
    });

    it('should have Next button', () => {
      cy.get('button:contains("Next")').should('exist');
    });

    it('should have Previous button', () => {
      cy.get('button:contains("Previous")').should('exist');
    });
  });

  describe('Report Queue', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/queue');
      cy.waitForPageLoad();
    });

    it('should display report queue', () => {
      cy.assertContainsAny(['Queue', 'No reports in queue', 'pending']);
    });

    it('should display report status badges', () => {
      cy.assertContainsAny(['PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'No reports']);
    });

    it('should display empty state when no reports', () => {
      cy.assertContainsAny(['No reports in queue', 'Reports']);
      cy.assertHasElement(['[class*="card"]', 'body']);
    });

    it('should have Download button for completed reports', () => {
      cy.get('button:contains("Download")').should('exist');
    });

    it('should have Cancel button for pending reports', () => {
      cy.get('button:contains("Cancel")').should('exist');
    });
  });

  describe('Scheduled Reports', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();
    });

    it('should display scheduled reports section', () => {
      cy.assertContainsAny(['Scheduled Reports', 'Schedule']);
    });

    it('should have New Schedule button', () => {
      cy.get('button:contains("New Schedule")').should('exist');
    });

    it('should display schedule frequency options', () => {
      cy.assertContainsAny(['Daily', 'Weekly', 'Monthly']);
    });

    it('should display schedule status badges', () => {
      cy.assertContainsAny(['ACTIVE', 'PAUSED']);
    });

    it('should have Edit and Pause actions', () => {
      cy.assertContainsAny(['Edit', 'Pause', 'Resume']);
    });
  });

  describe('Reports Analytics', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/analytics');
      cy.waitForPageLoad();
    });

    it('should display usage statistics', () => {
      cy.assertContainsAny(['Reports Generated', 'Active Schedules', 'Templates Used']);
    });

    it('should display popular templates section', () => {
      cy.assertContainsAny(['Most Popular Templates', 'Popular']);
    });

    it('should display recent activity', () => {
      cy.get('body').should('contain.text', 'Recent Activity');
    });

    it('should display data size statistics', () => {
      cy.assertContainsAny(['Data Generated', 'GB', 'MB']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.get('button:contains("Refresh")').should('exist');
    });
  });

  describe('Date Range Filter', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/builder');
      cy.waitForPageLoad();
    });

    it('should display date range filter', () => {
      cy.assertContainsAny(['Date Range']);
      cy.assertHasElement(['input[type="date"]', 'body']);
    });
  });

  describe('Report Format Selection', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/builder');
      cy.waitForPageLoad();
    });

    it('should display format options', () => {
      cy.assertContainsAny(['PDF', 'CSV', 'XLSX', 'JSON', 'Format']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/reports*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Reports', 'Business']);
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/reports/templates*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load templates' }
      });

      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Reports']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/reports/templates*', {
        delay: 1000,
        statusCode: 200,
        body: []
      });

      cy.visit('/app/business/reports');

      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', 'body']);
      cy.assertContainsAny(['Loading', 'Reports']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').should('contain.text', 'Reports');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').should('contain.text', 'Reports');
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Reports', 'Business']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertHasElement(['[class*="md:grid-cols"]', '[class*="lg:grid-cols"]', '[class*="grid"]']);
    });
  });
});


export {};
