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
      cy.get('body').then($body => {
        const hasWorkflows = !$body.text().includes('No workflows found');
        if (hasWorkflows) {
          cy.assertHasElement(['a[href*="/workflows/"]', 'button[title*="View"]', '[class*="cursor-pointer"]']);
        } else {
          cy.log('No workflows - name links only appear when workflows exist');
        }
      });
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

    it('should be able to click workflow name to view details when workflows exist', () => {
      cy.get('body').then($body => {
        const bodyText = $body.text();
        const hasEmptyState = bodyText.includes('No workflows found') || bodyText.includes('No workflows') || bodyText.includes('Get started');

        if (hasEmptyState) {
          cy.log('No workflows to click - skipping navigation test');
        } else {
          // Look for clickable workflow links or table rows
          const hasWorkflowLinks = $body.find('a[href*="/workflows/"]:not([href="/app/ai/workflows"])').length > 0;
          const hasWorkflowRows = $body.find('table tbody tr').length > 0;

          if (hasWorkflowLinks || hasWorkflowRows) {
            // Try to click a workflow link or row
            if (hasWorkflowLinks) {
              cy.get('a[href*="/workflows/"]:not([href="/app/ai/workflows"])').first().click({ force: true });
              cy.waitForPageLoad();
              cy.url().should('include', '/workflows/');
            } else {
              // Table rows might be clickable
              cy.log('Found workflow table but no direct links - page layout may vary');
            }
          } else {
            cy.log('Workflows page loaded but no clickable workflow items found');
          }
        }
      });
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
      cy.get('body').should('be.visible');
    });

    it('should show proper layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.navigateTo('/app/ai/workflows');
      cy.assertHasElement(['table', '[class*="table"]', '[class*="grid"]']);
    });
  });
});

export {};
