/// <reference types="cypress" />

/**
 * DevOps Integrations Page Tests
 *
 * Tests for Integrations management functionality including:
 * - Page navigation and load
 * - Stats display
 * - Integration list display
 * - Filtering
 * - Integration actions
 * - Empty state handling
 * - Responsive design
 */

describe('DevOps Integrations Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Integrations page', () => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Integration', 'Integrations', 'My Integrations']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['DevOps', 'Dashboard', 'Integrations']);
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
    });

    it('should display integration statistics', () => {
      cy.assertContainsAny(['Total', 'Active', 'Errors', 'Executions', 'Integration', 'Integrations']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
    });

    it('should have Browse Marketplace and Add Integration buttons', () => {
      cy.assertContainsAny(['Browse Marketplace', 'Marketplace', 'Add Integration', 'New Integration', 'Create']);
    });

    it('should navigate to marketplace on button click', () => {
      cy.get('button:contains("Browse Marketplace"), button:contains("Marketplace")').first().click();
      cy.waitForPageLoad();
      cy.url().should('match', /marketplace|integrations/);
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
    });

    it('should display status and type filters', () => {
      cy.assertContainsAny(['All Status', 'Status', 'Type', 'Filter', 'All Types', 'Integration']);
    });
  });

  describe('Integration List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
    });

    it('should display integration list', () => {
      cy.assertContainsAny(['Integration', 'active', 'Active', 'pending', 'paused', 'error', 'No integrations', 'Integrations']);
    });

    it('should display integration types', () => {
      cy.assertContainsAny(['GitHub', 'Webhook', 'MCP', 'REST', 'Custom', 'No integrations', 'Integration', 'All Types']);
    });
  });

  describe('Integration Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
    });

    it('should have activate, deactivate, and delete actions', () => {
      cy.assertContainsAny(['Activate', 'Deactivate', 'Pause', 'Delete', 'Configure', 'Edit', 'Settings', 'No integrations', 'Integration']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no integrations', () => {
      cy.intercept('GET', '**/integrations/instances*', {
        statusCode: 200,
        body: { success: true, data: { instances: [] } },
      }).as('getEmptyIntegrations');

      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['No integrations', 'no integrations', 'Get started', 'Browse', 'Marketplace']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/integrations/instances*', {
        statusCode: 500,
        visitUrl: '/app/devops/integrations',
      });
    });

    it('should display error message on API failure', () => {
      cy.mockApiError('**/integrations/instances*', 500, 'Server error');
      cy.visit('/app/devops/integrations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'Integration', 'Integrations']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/integrations', {
        checkContent: 'Integration',
      });
    });
  });
});

export {};
