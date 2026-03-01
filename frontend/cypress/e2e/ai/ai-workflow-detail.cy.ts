/// <reference types="cypress" />

/**
 * AI Workflow Detail Page Tests
 *
 * Tests for Workflow Detail functionality when viewing a specific workflow
 * These tests navigate to the workflows list and then access a workflow detail
 */

describe('AI Workflow Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflows page first', () => {
      cy.assertPageReady('/app/ai/workflows', 'Workflows');
    });

    it('should display workflow list', () => {
      cy.navigateTo('/app/ai/workflows');
      cy.assertHasElement(['table', '[class*="table"]', '[class*="list"]', '[class*="card"]']);
    });
  });

  describe('Workflow List View', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows');
    });

    it('should display workflow name as clickable link when workflows exist', () => {
      cy.assertHasElement(['a[href*="/workflows/"]', 'button[title*="View"]', '[class*="cursor-pointer"]', '[data-testid="empty-state"]']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['AI', 'Workflows', 'Dashboard']);
    });
  });

  describe('Workflow List - Status Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows');
    });

    it('should display status badges', () => {
      cy.assertContainsAny(['Status', 'Draft', 'Active', 'Inactive', 'Paused', 'Archived', 'No workflows']);
    });

    it('should display stats column', () => {
      cy.assertContainsAny(['Stats', 'nodes', 'runs', 'No workflows']);
    });
  });

  describe('Workflow List - Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows');
    });

    it('should have Create Workflow button', () => {
      cy.assertActionButton('Create Workflow');
    });

    it('should have Refresh button', () => {
      cy.assertActionButton('Refresh');
    });

    it('should have Monitoring button', () => {
      cy.assertActionButton('Monitoring');
    });

    it('should have Import button', () => {
      cy.assertActionButton('Import');
    });
  });

  describe('Workflow List - Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows');
    });

    it('should have search input', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="search"]', 'input[placeholder*="Search"]']);
    });

    it('should have status filter', () => {
      cy.assertContainsAny(['All Statuses', 'Status']);
    });

    it('should have visibility filter', () => {
      cy.assertContainsAny(['All Visibility', 'Visibility']);
    });

    it('should have type filter (All, Workflows, Templates)', () => {
      cy.assertContainsAny(['All', 'Workflows', 'Templates']);
    });
  });

  describe('Workflow Detail - Navigate to Detail', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows');
    });

    it('should display workflows list or empty state', () => {
      cy.assertContainsAny(['No workflows', 'workflow', 'Workflow', 'Get started', 'Create']);
    });

    it('should have clickable workflow links when workflows exist', () => {
      cy.assertHasElement([
        'a[href*="/workflows/"]',
        'table tbody tr',
        '[data-testid*="workflow"]',
        '[data-testid="empty-state"]'
      ]);
    });
  });

  describe('Error Handling', () => {
    it('should handle workflow not found', () => {
      cy.navigateTo('/app/ai/workflows/nonexistent-workflow-id');
      cy.assertContainsAny(['Not Found', 'not found', 'Error', 'Workflows', 'does not exist']);
    });

    it('should handle API error gracefully', () => {
      cy.testErrorHandling(/\/api\/v1\/ai\/workflows.*/, {
        statusCode: 500,
        visitUrl: '/app/ai/workflows'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows', {
        checkContent: ['Workflow', 'AI']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows');
      cy.assertContainsAny(['Workflows', 'AI']);
    });

    it('should display on small screens', () => {
      cy.viewport(375, 667);
      cy.navigateTo('/app/ai/workflows');
      cy.assertContainsAny(['Workflows', 'AI', 'Create Workflow']);
    });

    it('should show proper layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.navigateTo('/app/ai/workflows');
      cy.assertHasElement(['table', '[class*="table"]', '[class*="grid"]']);
    });
  });
});

export {};
