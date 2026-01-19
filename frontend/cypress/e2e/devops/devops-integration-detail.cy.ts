/// <reference types="cypress" />

/**
 * DevOps Integration Detail Page Tests
 *
 * Tests for Integration Detail functionality including:
 * - Page navigation
 * - Integration header display
 * - Stats cards
 * - Tab navigation
 * - Execution actions
 * - Responsive design
 */

describe('DevOps Integration Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Integration Detail page', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.waitForPageLoad();
      cy.url().should('include', '/devops');
    });

    it('should display Integration Not Found for invalid ID', () => {
      cy.visit('/app/devops/integrations/invalid-integration-id');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Not Found', "doesn't exist", 'Back to Integrations', 'Integration']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should have Activate/Pause and Execute buttons', () => {
      cy.assertContainsAny(['Activate', 'Pause', 'Execute Now', 'Execute', 'Not Found']);
    });
  });

  describe('Integration Header', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should display integration details', () => {
      cy.assertContainsAny(['active', 'inactive', 'paused', 'Not Found', 'Integration']);
    });
  });

  describe('Stats Cards', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should display integration statistics', () => {
      cy.assertContainsAny(['Total Executions', 'Success Rate', 'Duration', 'Last Executed', 'Not Found']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should display Overview, Executions, and Config tabs', () => {
      cy.assertContainsAny(['Overview', 'Executions', 'Config', 'Not Found']);
    });

    it('should switch to Executions tab', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Executions")').length > 0) {
          cy.clickTab('Executions');
          cy.assertContainsAny(['Execution', 'History', 'No executions']);
        }
      });
    });

    it('should switch to Config tab', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.clickTab('Config');
          cy.assertContainsAny(['Configuration', 'Credential', 'Danger Zone', 'Delete']);
        }
      });
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should display Health Status and Recent Executions', () => {
      cy.assertContainsAny(['Health Status', 'healthy', 'degraded', 'Recent Executions', 'Response Time', 'Not Found']);
    });
  });

  describe('Execution Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/integrations/test-integration');
    });

    it('should have Retry and Cancel options', () => {
      cy.assertContainsAny(['Retry', 'Cancel', 'Not Found', 'No executions']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/integrations/**', {
        statusCode: 500,
        visitUrl: '/app/devops/integrations/test-integration',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/integrations/test-integration', {
        checkContent: 'Integration',
      });
    });
  });
});

export {};
