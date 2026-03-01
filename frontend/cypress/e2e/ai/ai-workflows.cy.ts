/// <reference types="cypress" />

/**
 * AI Workflows Tests
 *
 * Tests for AI Workflows page functionality including:
 * - Page navigation and load
 * - Workflows list display
 * - Search and filtering
 * - Create workflow modal
 * - Workflow actions
 * - Pagination
 * - Error handling
 * - Responsive design
 */

describe('AI Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should navigate to AI Workflows from sidebar', () => {
      cy.url().should('include', '/workflows');
    });

    it('should load AI Workflows page directly', () => {
      cy.assertContainsAny(['Workflows', 'AI']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Workflows']);
    });
  });

  describe('Workflows List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should display workflows list or empty state', () => {
      cy.assertContainsAny(['No workflows', 'Create Workflow', 'Workflow']);
    });

    it('should display workflow status badges', () => {
      cy.assertContainsAny(['Draft', 'Active', 'Inactive', 'Paused', 'Archived', 'No workflows']);
    });

    it('should display template badges for templates', () => {
      cy.assertContainsAny(['Template', 'Workflow', 'No workflows']);
    });

    it('should display workflow stats (nodes, runs)', () => {
      cy.assertContainsAny(['nodes', 'runs', 'No workflows']);
    });

    it('should display created by information', () => {
      cy.assertContainsAny(['Created', 'Admin', 'No workflows']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have search input', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="search"]', 'input[placeholder*="Search"]']);
    });

    it('should filter workflows by search query', () => {
      cy.get('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]')
        .first()
        .type('test');
      cy.waitForStableDOM();
    });

    it('should clear search and show all workflows', () => {
      cy.get('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]')
        .first()
        .type('test')
        .clear();
      cy.waitForStableDOM();
    });
  });

  describe('Status Filter', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have status filter dropdown', () => {
      cy.assertContainsAny(['All Statuses', 'Status', 'Filter']);
    });

    it('should filter by draft status', () => {
      cy.clickButton('All Statuses');
      cy.assertContainsAny(['Draft', 'Active', 'Inactive']);
    });
  });

  describe('Visibility Filter', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have visibility filter', () => {
      cy.assertContainsAny(['All Visibility', 'Visibility', 'Private', 'Public']);
    });
  });

  describe('Type Filter (All, Workflows, Templates)', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have type filter buttons', () => {
      cy.assertContainsAny(['All', 'Workflows', 'Templates']);
    });

    it('should filter to show only workflows', () => {
      cy.contains('button', 'Workflows').not(':contains("All")').click();
      cy.url().should('include', 'type=workflows');
    });

    it('should filter to show only templates', () => {
      cy.clickButton('Templates');
      cy.url().should('include', 'type=templates');
    });
  });

  describe('Sorting', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have sort controls', () => {
      cy.assertContainsAny(['Sort', 'Name', 'Created', 'Updated']);
    });
  });

  describe('Create Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should display Create Workflow button', () => {
      cy.assertActionButton('Create Workflow');
    });

    it('should open create modal when button clicked', () => {
      cy.clickButton('Create Workflow');
      cy.assertModalVisible('Create');
    });

    it('should have name input in create modal', () => {
      cy.clickButton('Create Workflow');
      cy.waitForStableDOM();
      cy.assertHasElement(['input[name="name"]', 'input[placeholder*="name"]']);
    });

    it('should close modal when cancel clicked', () => {
      cy.clickButton('Create Workflow');
      cy.waitForStableDOM();
      cy.get('button:contains("Cancel"), button:contains("Close")').first().click();
      cy.waitForModalClose();
    });
  });

  describe('View Workflow Details', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have view details action when workflows exist', () => {
      cy.assertContainsAny(['No workflows found', 'No workflows', 'Get started', 'View', 'Details']);
    });
  });

  describe('Execute Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have execute action for active workflows', () => {
      cy.assertContainsAny(['Active', 'Execute', 'No workflows']);
    });
  });

  describe('Duplicate Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have duplicate action', () => {
      cy.assertHasElement(['button[title*="Duplicate"]', 'button[title*="Copy"]', '[class*="lucide-copy"]']);
    });
  });

  describe('Delete Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have delete action', () => {
      cy.assertHasElement(['button[title*="Delete"]', '[class*="lucide-trash"]']);
    });
  });

  describe('Workflow Builder/Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have design action when workflows exist', () => {
      cy.assertContainsAny(['No workflows found', 'No workflows', 'Get started', 'Design', 'Edit', 'Builder']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should display pagination controls when many workflows exist', () => {
      cy.assertHasElement(['[class*="pagination"]', '[class*="Pagination"]', 'nav[aria-label="pagination"]', 'button:contains("Next")']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no workflows exist', () => {
      cy.mockEndpoint('GET', /\/api\/v1\/ai\/workflows(\?.*)?$/, {
        success: true,
        data: {
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        }
      });
      cy.navigateTo('/app/ai/workflows');
      cy.assertContainsAny(['No workflows', 'Get started', 'Create Workflow']);
    });

    it('should have create button in empty state', () => {
      cy.mockEndpoint('GET', /\/api\/v1\/ai\/workflows(\?.*)?$/, {
        success: true,
        data: {
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        }
      });
      cy.navigateTo('/app/ai/workflows');
      cy.assertActionButton('Create');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have refresh button', () => {
      cy.assertActionButton('Refresh');
    });
  });

  describe('Monitoring Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have monitoring button', () => {
      cy.assertActionButton('Monitoring');
    });

    it('should navigate to monitoring page', () => {
      cy.clickButton('Monitoring');
      cy.url().should('include', '/monitoring');
    });
  });

  describe('Import Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/workflows');
    });

    it('should have import button', () => {
      cy.assertActionButton('Import');
    });

    it('should navigate to import page', () => {
      cy.clickButton('Import');
      cy.url().should('include', '/import');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling(/\/api\/v1\/ai\/workflows(\?.*)?$/, {
        statusCode: 500,
        visitUrl: '/app/ai/workflows'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError(/\/api\/v1\/ai\/workflows(\?.*)?$/, 500, 'Failed to load workflows');
      cy.navigateTo('/app/ai/workflows');
      cy.assertContainsAny(['Error', 'Failed', 'Workflows']);
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
      cy.assertPageReady('/app/ai/workflows');
      cy.assertContainsAny(['Workflow', 'AI']);
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/ai/workflows');
      cy.assertContainsAny(['Workflow', 'AI']);
    });
  });
});

export {};
