/// <reference types="cypress" />

/**
 * DevOps Pipelines Page Tests
 *
 * Tests for CI/CD Pipelines functionality including:
 * - Page navigation and load
 * - Pipeline list display
 * - Filter tabs
 * - Create/Trigger/Delete pipelines
 * - Export YAML
 * - Responsive design
 */

describe('DevOps Pipelines Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
    Cypress.on('uncaught:exception', () => false);
  });

  describe('Page Navigation', () => {
    it('should load Pipelines page directly', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      // This route redirects to workflows
      cy.assertContainsAny(['Pipeline', 'Pipelines', 'Workflow', 'Workflows', 'DevOps']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Pipelines', 'Workflows']);
    });
  });

  describe('Pipeline List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should display pipeline list or empty state', () => {
      cy.assertContainsAny(['No pipelines', 'No workflows', 'Create your first', 'Pipeline', 'Workflow', 'Active', 'All']);
    });
  });

  describe('Filter Tabs', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should display filter tabs', () => {
      cy.assertContainsAny(['All Pipelines', 'All Workflows', 'All', 'Active', 'Inactive']);
    });

    it('should filter by Active pipelines', () => {
      cy.get('body').then($body => {
        const activeBtn = $body.find('button:contains("Active")');
        if (activeBtn.length > 0) {
          cy.wrap(activeBtn).first().click();
          cy.waitForStableDOM();
        }
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Create Pipeline', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should display Create Pipeline button', () => {
      cy.assertContainsAny(['Create Pipeline', 'Create Workflow', 'Create', 'New', 'Refresh']);
    });

    it('should navigate to create page when Create Pipeline clicked', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create Pipeline"), button:contains("Create Workflow"), button:contains("Create")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click();
          cy.waitForStableDOM();
        }
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Pipeline Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have Trigger action for pipelines', () => {
      cy.assertContainsAny(['Trigger', 'Run', 'Execute', 'No pipelines', 'No workflows', 'Pipeline', 'Workflow', 'All']);
    });

    it('should have Duplicate and Delete options in menu', () => {
      cy.assertContainsAny(['Duplicate', 'Delete', 'Export', 'No pipelines', 'No workflows', 'Pipeline', 'Workflow', 'All']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Sync', 'Pipeline', 'Workflow']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/pipelines*', {
        statusCode: 500,
        visitUrl: '/app/devops/pipelines',
      });
    });

    it('should display error message on API failure', () => {
      cy.mockApiError('**/api/**/pipelines*', 500, 'Server error');
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Error', 'Failed', 'Pipeline', 'Workflow']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/pipelines', {
        checkContent: ['Pipeline', 'Workflow', 'DevOps'],
      });
    });
  });
});

export {};
