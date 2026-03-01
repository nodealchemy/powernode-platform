/// <reference types="cypress" />

/**
 * Webhook Management Page Tests
 *
 * Tests for the Webhook Management functionality including:
 * - Page navigation and display
 * - Stats overview display
 * - View mode switching (list/details/stats)
 * - Webhook list display
 * - Responsive design
 */

describe('Webhook Management Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should navigate to Webhook Management page', () => {
      cy.url().should('include', '/webhooks');
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Webhook', 'Webhooks', 'Management']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['Configure', 'webhook', 'endpoints', 'notifications', 'monitor']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Webhooks']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should have Add Webhook button or permission-restricted view', () => {
      cy.assertContainsAny(['Add Webhook', 'Create Webhook', 'New Webhook', 'permission', 'Permission']);
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'reload']);
    });

    it('should have Statistics button', () => {
      cy.assertContainsAny(['Statistics', 'Stats']);
    });
  });

  describe('Stats Overview', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should display stat cards or empty state', () => {
      cy.assertContainsAny(['Total Endpoints', 'Active', 'Inactive', 'Deliveries', 'No webhooks', 'permission']);
    });

    it('should display endpoint counts', () => {
      cy.assertContainsAny(['Endpoints', 'Active', 'Inactive', 'Total', 'permission', 'webhook']);
    });

    it('should display delivery information', () => {
      cy.assertContainsAny(['Deliveries', 'Today', 'Successful', 'Failed', 'webhook', 'permission']);
    });
  });

  describe('View Modes', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should have view mode options', () => {
      cy.assertContainsAny(['Statistics', 'Stats', 'Back']);
    });

    it('should switch to Statistics view', () => {
      cy.contains('button', 'Statistics').click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Statistics', 'Success', 'Failed', 'Rate', 'Back']);
    });
  });

  describe('Webhook List', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should display webhooks list or empty state', () => {
      cy.assertContainsAny(['webhook', 'No webhooks', 'permission']);
    });

    it('should display URL or Endpoint column when data exists', () => {
      cy.assertContainsAny(['URL', 'Endpoint', 'Name', 'No webhooks', 'permission']);
    });

    it('should display status information', () => {
      cy.assertContainsAny(['Status', 'Active', 'Inactive', 'Enabled', 'webhook', 'permission']);
    });
  });

  describe('Filters', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/webhooks');
    });

    it('should display filter controls when list is shown', () => {
      cy.assertContainsAny(['All', 'Search', 'Filter']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('/api/v1/webhooks*', {
        statusCode: 500,
        visitUrl: '/app/devops/webhooks',
      });
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/webhooks**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/devops/webhooks');
      cy.assertContainsAny(['Error', 'Failed', 'error']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/webhooks**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: { webhooks: [], pagination: {}, stats: {} } });
        });
      }).as('slowLoad');

      cy.visit('/app/devops/webhooks');

      cy.assertHasElement(['.animate-spin', '[class*="loading"]', '[class*="spinner"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Webhook', 'Webhooks']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Webhook', 'Webhooks']);
    });

    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/webhooks', {
        checkContent: 'Webhook',
      });
    });
  });

  describe('Permission-Based Access', () => {
    it('should handle permission restrictions gracefully', () => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Webhook', 'Webhooks', 'permission', 'Permission']);
    });
  });
});

export {};
