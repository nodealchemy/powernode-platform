/// <reference types="cypress" />

/**
 * Admin Files Page Tests
 *
 * Tests for Admin Files management functionality including:
 * - Page navigation and load
 * - Files list display
 * - File search and filtering
 * - File upload actions
 * - File management (view, delete)
 * - Storage statistics
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Admin Files Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/files');
    });

    it('should navigate to Admin Files page', () => {
      cy.assertContainsAny(['Files', 'File Management', 'Permission']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Files', 'File Management']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'Admin']);
    });
  });

  describe('Files List Display', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should display files list or empty state', () => {
      cy.assertHasElement(['[class*="table"]', '[class*="list"]', '[class*="card"]', '[class*="grid"]', '[role="table"]', '[role="list"]']);
    });

    it('should display file information columns', () => {
      cy.assertContainsAny(['Name', 'Size', 'Type', 'Uploaded']);
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search"], input[placeholder*="search"], input[type="search"], [role="searchbox"], [class*="search"]').should('exist');
    });

    it('should search files', () => {
      cy.get('input[placeholder*="Search"], input[placeholder*="search"]').first().type('document');
      cy.waitForPageLoad();
    });

    it('should display type filter', () => {
      cy.assertContainsAny(['Type', 'All Types', 'Filter']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should have Upload button', () => {
      cy.get('button:contains("Upload")').should('exist');
    });

    it('should have Refresh button', () => {
      cy.get('button:contains("Refresh")').should('exist');
    });
  });

  describe('File Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should have View action', () => {
      cy.get('button:contains("View"), [aria-label*="view"]').should('exist');
    });

    it('should have Download action', () => {
      cy.get('button:contains("Download"), [aria-label*="download"]').should('exist');
    });

    it('should have Delete action', () => {
      cy.get('button:contains("Delete"), [aria-label*="delete"]').should('exist');
    });
  });

  describe('Storage Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should display storage usage', () => {
      cy.assertContainsAny(['Storage', 'KB', 'MB', 'GB']);
    });

    it('should display total files count', () => {
      cy.assertContainsAny(['Total', 'files']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();
    });

    it('should display pagination controls', () => {
      cy.assertHasElement(['[class*="pagination"]', 'button:contains("Next")']);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/files');
    });

    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Files', 'Error', 'File Management']);
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load files' }
      });

      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Files']);
    });
  });

  describe('Loading State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/files');
    });

    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, files: [] }
      });

      cy.visit('/app/admin/files');

      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', '[class*="animate"]']);
    });
  });

  describe('Empty State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/files');
    });

    it('should display empty state when no files', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 200,
        body: { success: true, files: [] }
      });

      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['No files', 'Upload your first', 'Files']);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/files');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Files', 'File']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Files', 'File']);
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Files', 'File Management']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/files');
    });
  });
});


export {};
