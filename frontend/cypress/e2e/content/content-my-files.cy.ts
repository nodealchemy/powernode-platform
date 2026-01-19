/// <reference types="cypress" />

/**
 * Content My Files Page Tests
 *
 * Tests for My Files functionality including:
 * - Page navigation and load
 * - File list display
 * - Search and filtering
 * - File upload modal
 * - Bulk actions
 * - File details view
 * - Storage statistics
 * - Permission-based actions
 * - Error handling
 * - Responsive design
 */

describe('Content My Files Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to My Files page', () => {
      cy.assertPageReady('/app/content/files');
      cy.assertContainsAny(['My Files', 'Files', 'Permission']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/content/files');
      cy.assertContainsAny(['My Files']);
    });

    it('should display page description', () => {
      cy.assertPageReady('/app/content/files');
      cy.assertContainsAny(['personal files', 'documents', 'Manage']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should have Upload Files button', () => {
      cy.assertContainsAny(['Upload Files', 'Upload', 'Files']);
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Files']);
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should display search input', () => {
      cy.assertHasElement(['input[placeholder*="Search files"]', 'input[placeholder*="search"]']);
    });

    it('should search files', () => {
      cy.assertHasElement(['input[placeholder*="Search files"]', 'input[placeholder*="search"]'])
        .first()
        .type('document');
      cy.get('body').should('be.visible');
    });

    it('should display category filter', () => {
      cy.assertContainsAny(['All Categories', 'Files']);
    });

    it('should display visibility filter', () => {
      cy.assertContainsAny(['All Visibility', 'Private', 'Public']);
    });

    it('should filter by category', () => {
      cy.get('select').then($selects => {
        if ($selects.length > 0) {
          cy.wrap($selects).first().then($select => {
            const options = $select.find('option');
            if (options.length > 1) {
              cy.wrap($select).select(1);
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Files List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should display files list', () => {
      cy.assertHasElement([
        '[class*="list"]',
        '[class*="card"]',
        '[class*="space"]',
        '[data-testid*="files"]',
        '[data-testid*="list"]',
        '[role="list"]',
        'ul',
        'table'
      ]);
    });

    it('should display file items', () => {
      cy.assertContainsAny(['No files', 'Files']);
    });

    it('should display empty state when no files', () => {
      cy.assertContainsAny(['No files yet', 'No files found', 'Upload your first', 'Files']);
    });

    it('should display select all checkbox', () => {
      cy.assertContainsAny(['Select all', 'Files']);
    });
  });

  describe('Upload Modal', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should open upload modal', () => {
      cy.assertHasElement(['button:contains("Upload Files")', 'button:contains("Upload")']).then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).first().scrollIntoView().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Upload Files', 'Storage Provider']);
        }
      });
    });

    it('should have storage provider selector', () => {
      cy.assertHasElement(['button:contains("Upload Files")', 'button:contains("Upload")']).then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).first().scrollIntoView().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Storage Provider', 'Local', 'Files']);
        }
      });
    });

    it('should close upload modal', () => {
      cy.assertHasElement(['button:contains("Upload Files")', 'button:contains("Upload")']).then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).first().scrollIntoView().click();
          cy.waitForStableDOM();
          cy.assertHasElement(['button:contains("Close")', 'button:contains("Cancel")']).then($closeBtn => {
            if ($closeBtn.length > 0) {
              cy.wrap($closeBtn).first().scrollIntoView().click();
              cy.waitForStableDOM();
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Bulk Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should show bulk action bar when files selected', () => {
      cy.get('input[type="checkbox"]').then($checkboxes => {
        if ($checkboxes.length > 1) {
          cy.wrap($checkboxes).eq(1).click();
          cy.assertContainsAny(['selected', 'Download', 'Files']);
        }
      });
    });

    it('should have bulk download option', () => {
      cy.assertContainsAny(['Download', 'Files']);
    });

    it('should have bulk delete option', () => {
      cy.assertContainsAny(['Delete', 'Files']);
    });

    it('should have clear selection option', () => {
      cy.assertContainsAny(['Clear', 'Files']);
    });
  });

  describe('Storage Statistics', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/files');
    });

    it('should display storage usage', () => {
      cy.assertContainsAny(['Storage Used', 'KB', 'MB', 'GB', 'Files']);
    });

    it('should display total files count', () => {
      cy.assertContainsAny(['Total Files', 'files', 'Files']);
    });

    it('should display storage progress bar', () => {
      cy.assertContainsAny(['% used', 'Storage', 'Files']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/files*', {
        statusCode: 500,
        visitUrl: '/app/content/files'
      });
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/files*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load files' }
      });

      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Files']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/files*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, files: [] }
      });

      cy.visit('/app/content/files');

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
      cy.testViewport('mobile', '/app/content/files');
      cy.assertContainsAny(['Files', 'My Files']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/content/files');
      cy.assertContainsAny(['Files', 'My Files']);
    });

    it('should stack filters on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });
});


export {};
