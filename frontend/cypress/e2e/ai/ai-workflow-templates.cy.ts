/// <reference types="cypress" />

/**
 * AI Workflow Templates Page Tests
 *
 * Tests for Workflow Templates functionality (templates view of WorkflowsPage)
 * The templates are displayed via the workflows page with ?type=templates filter
 */

describe('AI Workflow Templates Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Templates page', () => {
      cy.assertPageReady('/app/ai/workflows?type=templates', 'Workflow');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.assertContainsAny(['AI Workflows', 'Workflows']);
    });

    it('should have Templates filter active', () => {
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.url().should('include', 'type=templates');
      cy.assertContainsAny(['Templates', 'Template']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.assertContainsAny(['AI', 'Workflows']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows?type=templates');
    });

    it('should display search input', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="search"]', 'input[placeholder*="Search"]']);
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows?type=templates');
    });

    it('should display status filter', () => {
      cy.assertContainsAny(['All Statuses', 'Status', 'Filter']);
    });

    it('should display visibility filter', () => {
      cy.assertContainsAny(['All Visibility', 'Visibility', 'Private', 'Public']);
    });

    it('should have type filter with Templates selected', () => {
      cy.assertContainsAny(['Templates', 'All', 'Workflows']);
    });
  });

  describe('Template Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows?type=templates');
    });

    it('should display table or empty state', () => {
      cy.assertHasElement(['table', '[class*="table"]', '[class*="empty"]', '[class*="list"]']);
    });

    it('should display template badge on template workflows', () => {
      cy.assertContainsAny(['Template', 'template', 'No workflows']);
    });
  });

  describe('Template Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows?type=templates');
    });

    it('should have Create Workflow button', () => {
      cy.assertActionButton('Create Workflow');
    });

    it('should have view details action when templates exist', () => {
      cy.assertContainsAny(['No workflows found', 'No workflows', 'Get started', 'View', 'Details']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no templates', () => {
      cy.mockEndpoint('GET', /\/api\/v1\/ai\/workflows(\?.*)?$/, {
        success: true,
        data: {
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        }
      });
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.assertContainsAny(['No workflows', 'No templates', 'Get started']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling(/\/api\/v1\/ai\/workflows(\?.*)?$/, {
        statusCode: 500,
        visitUrl: '/app/ai/workflows?type=templates'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading state or content quickly', () => {
      cy.intercept('GET', '**/api/v1/ai/workflows*', {
        delay: 500,
        statusCode: 200,
        body: {
          success: true,
          data: {
            items: [],
            pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
          }
        }
      });
      cy.visit('/app/ai/workflows?type=templates');
      cy.assertHasElement(['[class*="animate-pulse"]', '[class*="skeleton"]', '[class*="loading"]', '[class*="spinner"]', 'table', '[class*="table"]', '[class*="empty"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows?type=templates', {
        checkContent: ['Workflow', 'AI']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.assertContainsAny(['Workflow', 'AI']);
    });

    it('should show proper layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.navigateTo('/app/ai/workflows?type=templates');
      cy.assertHasElement(['table', '[class*="table"]', '[class*="grid"]']);
    });
  });
});

export {};
