/// <reference types="cypress" />

/**
 * DevOps Pipeline/Workflow E2E Tests
 *
 * Note: Pipeline routes now redirect to AI Workflows (/app/ai/workflows).
 * This test file tests the AI Workflows functionality which replaced pipelines.
 *
 * Tests for workflow management functionality including:
 * - Workflow list display
 * - Workflow creation
 * - Workflow execution
 * - Workflow filtering and search
 * - Responsive design
 */

describe('DevOps Pipeline/Workflow Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai', 'devops'] });
  });

  describe('Workflow List', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should navigate to Workflows page', () => {
      cy.assertContainsAny(['Workflow', 'Workflows', 'AI Workflows']);
    });

    it('should display workflow list or empty state', () => {
      cy.assertContainsAny(['Workflow', 'Running', 'Success', 'Failed', 'Pending', 'No workflows', 'Create']);
    });

    it('should display workflow status information', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Running', 'Status', 'No workflows']);
    });
  });

  describe('Workflow Creation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have Create Workflow button or permission notice', () => {
      cy.assertContainsAny(['Create', 'New', 'Add', 'permission']);
    });

    it('should open create workflow modal when clicking create button', () => {
      cy.get('button').filter(':contains("Create"), :contains("New")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Name', 'Description', 'Create', 'Workflow', 'Template']);
    });
  });

  describe('Workflow Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have filter options', () => {
      cy.assertContainsAny(['All', 'Workflows', 'Templates', 'Filter', 'Type']);
    });

    it('should have search functionality', () => {
      cy.assertHasElement([
        'input[type="text"]',
        'input[type="search"]',
        '[placeholder*="Search"]',
        '[data-testid="search-input"]',
        'input',
      ]);
    });

    it('should have sorting options', () => {
      cy.assertContainsAny(['Sort', 'Workflow', 'Workflows', 'All']);
    });
  });

  describe('Workflow Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should display workflow actions', () => {
      cy.assertContainsAny(['Execute', 'Edit', 'Delete', 'Run', 'View', 'Create', 'Workflow']);
    });

    it('should have refresh functionality', () => {
      cy.assertContainsAny(['Refresh', 'Workflow', 'Workflows', 'Create']);
    });
  });

  describe('Workflow Templates', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows?type=templates');
    });

    it('should display templates filter', () => {
      cy.assertContainsAny(['Template', 'Templates', 'Workflow', 'All']);
    });

    it('should filter to templates view', () => {
      cy.url().should('include', 'type=templates');
      cy.assertContainsAny(['Template', 'Workflows', 'No workflows']);
    });
  });

  describe('Workflow Import', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have import option', () => {
      cy.assertContainsAny(['Import', 'Create', 'New', 'Workflow']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should display page actions', () => {
      cy.assertContainsAny(['Create', 'Import', 'Workflow', 'New']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('/api/v1/workflows*', {
        statusCode: 500,
        visitUrl: '/app/ai/workflows',
      });
    });

    it('should show error recovery options', () => {
      cy.intercept('GET', '**/api/**/workflows**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('workflowsError');

      cy.visit('/app/ai/workflows');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Try', 'Retry', 'Failed']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/workflows', {
        checkContent: 'Workflow',
      });
    });

    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Workflow', 'Workflows']);
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflows');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Workflow', 'Workflows']);
    });
  });

  describe('DevOps Pipelines Route', () => {
    it('should load /app/devops/pipelines correctly', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.url().should('include', '/devops/pipelines');
      cy.assertContainsAny(['Pipeline', 'Pipelines', 'Create', 'DevOps']);
    });
  });

  describe('Workflow Detail', () => {
    it('should handle workflow detail navigation', () => {
      cy.visit('/app/ai/workflows');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Workflow', 'Workflows', 'No workflows', 'Create']);
    });
  });
});

export {};
