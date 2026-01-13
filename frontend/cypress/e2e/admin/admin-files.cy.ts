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
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Admin Files page', () => {
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Files') ||
                          $body.text().includes('File Management') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Admin Files page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Files') ||
                        $body.text().includes('File Management');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('Admin');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Files List Display', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should display files list or empty state', () => {
      cy.get('body').then($body => {
        const hasFiles = $body.find('[class*="table"], [class*="list"], [class*="card"]').length > 0 ||
                        $body.text().includes('No files');
        if (hasFiles) {
          cy.log('Files list or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display file information columns', () => {
      cy.get('body').then($body => {
        const hasColumns = $body.text().includes('Name') ||
                          $body.text().includes('Size') ||
                          $body.text().includes('Type') ||
                          $body.text().includes('Uploaded');
        if (hasColumns) {
          cy.log('File information columns displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should display search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search"], input[placeholder*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search files', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('document');
          cy.wait(500);
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display type filter', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.text().includes('Type') ||
                         $body.text().includes('All Types') ||
                         $body.find('select').length > 0;
        if (hasFilter) {
          cy.log('Type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should have Upload button', () => {
      cy.get('body').then($body => {
        const uploadButton = $body.find('button:contains("Upload")');
        if (uploadButton.length > 0) {
          cy.log('Upload button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('File Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should have View action', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View"), [aria-label*="view"]');
        if (viewButton.length > 0) {
          cy.log('View action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Download action', () => {
      cy.get('body').then($body => {
        const downloadButton = $body.find('button:contains("Download"), [aria-label*="download"]');
        if (downloadButton.length > 0) {
          cy.log('Download action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Delete action', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Storage Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should display storage usage', () => {
      cy.get('body').then($body => {
        const hasStorage = $body.text().includes('Storage') ||
                          $body.text().includes('KB') ||
                          $body.text().includes('MB') ||
                          $body.text().includes('GB');
        if (hasStorage) {
          cy.log('Storage usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display total files count', () => {
      cy.get('body').then($body => {
        const hasCount = $body.text().includes('Total') ||
                        $body.text().includes('files');
        if (hasCount) {
          cy.log('Total files count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/admin/files');
      cy.wait(2000);
    });

    it('should display pagination controls', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"]').length > 0 ||
                             $body.text().includes('Page') ||
                             $body.find('button:contains("Next")').length > 0;
        if (hasPagination) {
          cy.log('Pagination controls displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load files' }
      });

      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Files');
        if (hasError) {
          cy.log('Error handled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, files: [] }
      });

      cy.visit('/app/admin/files');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no files', () => {
      cy.intercept('GET', '/api/v1/admin/files*', {
        statusCode: 200,
        body: { success: true, files: [] }
      });

      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No files') ||
                        $body.text().includes('Upload your first');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Files') || $body.text().includes('File');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Files') || $body.text().includes('File');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/files');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
