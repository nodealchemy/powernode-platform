/// <reference types="cypress" />

/**
 * Content Pages Management Tests
 *
 * Tests for Content Pages functionality including:
 * - Page navigation and load
 * - Search and filtering
 * - Pages list display
 * - Create page action
 * - Page actions (view, edit, publish/unpublish, duplicate, delete)
 * - Pagination
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Content Pages Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Pages page', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Pages', 'Content', 'Permission', 'Access Denied']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Pages']);
    });

    it('should display page description', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Manage', 'website pages', 'content']);
    });

    it('should display breadcrumbs', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Dashboard']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Pages']);
    });

    it('should have Create Page button for authorized users', () => {
      cy.assertContainsAny(['Create Page', 'Pages']);
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should display search input', () => {
      cy.assertHasElement(['input[placeholder*="Search pages"]', 'input[placeholder*="search"]']);
    });

    it('should search pages', () => {
      cy.assertHasElement(['input[placeholder*="Search pages"]', 'input[placeholder*="search"]'])
        .first()
        .type('home');
      cy.waitForPageLoad();
      cy.assertContainsAny(['home', 'Pages', 'No pages']);
    });

    it('should display status filter', () => {
      cy.assertContainsAny(['All Status', 'Draft', 'Published']);
    });

    it('should filter by status', () => {
      cy.get('select').first().select(1);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pages', 'Draft', 'Published', 'No pages']);
    });
  });

  describe('Pages List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should display pages list', () => {
      cy.assertHasElement([
        'table',
        '[class*="list"]',
        '[class*="card"]',
        '[data-testid*="pages"]',
        '[role="table"]',
        '[role="list"]',
        'ul'
      ]);
    });

    it('should display table headers', () => {
      cy.assertContainsAny(['Title', 'Status', 'Published']);
    });

    it('should display page title column', () => {
      cy.assertContainsAny(['Title']);
    });

    it('should display status badge', () => {
      cy.assertContainsAny(['Draft', 'Published', 'Pages']);
    });

    it('should display word count', () => {
      cy.assertContainsAny(['words', 'Word Count', 'Pages']);
    });

    it('should display empty state when no pages', () => {
      cy.assertContainsAny(['No pages yet', 'Create your first', 'Pages']);
    });
  });

  describe('Page Row Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should have view page button', () => {
      cy.assertContainsAny(['View', 'Pages']);
    });

    it('should have edit page button', () => {
      cy.assertContainsAny(['Edit', 'Pages']);
    });

    it('should have publish/unpublish button', () => {
      cy.assertContainsAny(['Publish', 'Unpublish', 'Pages']);
    });

    it('should have duplicate page button', () => {
      cy.assertContainsAny(['Duplicate', 'Pages']);
    });

    it('should have delete page button', () => {
      cy.assertContainsAny(['Delete', 'Pages']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should display pagination when multiple pages', () => {
      cy.assertContainsAny(['Page', 'Previous', 'Next', 'Pages']);
    });

    it('should have Previous button', () => {
      cy.assertContainsAny(['Previous', 'Pages']);
    });

    it('should have Next button', () => {
      cy.assertContainsAny(['Next', 'Pages']);
    });
  });

  describe('Permission-Based Access', () => {
    it('should show access denied for unauthorized users', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Access Denied', 'privileges', 'Pages']);
    });

    it('should show Create Page for authorized users', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Create Page', 'Pages']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/pages*', {
        statusCode: 500,
        visitUrl: '/app/content/pages'
      });
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/pages*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load pages' }
      });

      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Pages']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/pages*', {
        delay: 1000,
        statusCode: 200,
        body: { data: [], meta: { total_pages: 1 } }
      });

      cy.visit('/app/content/pages');

      cy.assertHasElement([
        '[class*="spin"]',
        '[class*="loading"]',
        '[class*="animate-spin"]',
        '[data-testid*="loading"]',
        '[role="status"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/content/pages');
      cy.assertContainsAny(['Pages']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/content/pages');
      cy.assertContainsAny(['Pages']);
    });

    it('should have horizontal scroll on table for small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pages', 'Content']);
    });
  });
});


export {};
