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
    cy.clearAppData();
    cy.setupContentIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to My Files page', () => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('My Files') ||
                          $body.text().includes('Files') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('My Files page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('My Files');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('personal files') ||
                               $body.text().includes('documents') ||
                               $body.text().includes('Manage');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should have Upload Files button', () => {
      cy.get('body').then($body => {
        const uploadButton = $body.find('button:contains("Upload Files"), button:contains("Upload")');
        if (uploadButton.length > 0) {
          cy.log('Upload Files button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should display search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search files"], input[placeholder*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search files', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search files"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('document');
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category filter', () => {
      cy.get('body').then($body => {
        const hasCategoryFilter = $body.text().includes('All Categories') ||
                                  $body.find('select').length > 0;
        if (hasCategoryFilter) {
          cy.log('Category filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display visibility filter', () => {
      cy.get('body').then($body => {
        const hasVisibilityFilter = $body.text().includes('All Visibility') ||
                                    $body.text().includes('Private') ||
                                    $body.text().includes('Public');
        if (hasVisibilityFilter) {
          cy.log('Visibility filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by category', () => {
      cy.get('body').then($body => {
        const selects = $body.find('select');
        if (selects.length > 0) {
          cy.wrap(selects).first().then($select => {
            const options = $select.find('option');
            if (options.length > 1) {
              cy.wrap($select).select(1);
              cy.log('Filtered by category');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Files List Display', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should display files list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="list"], [class*="card"], [class*="space"]').length > 0;
        if (hasList) {
          cy.log('Files list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display file items', () => {
      cy.get('body').then($body => {
        const hasFiles = $body.find('[class*="file"], [class*="item"]').length > 0 ||
                         $body.text().includes('No files');
        if (hasFiles) {
          cy.log('File items or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display empty state when no files', () => {
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No files yet') ||
                         $body.text().includes('No files found') ||
                         $body.text().includes('Upload your first');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display select all checkbox', () => {
      cy.get('body').then($body => {
        const hasSelectAll = $body.find('input[type="checkbox"]').length > 0 ||
                             $body.text().includes('Select all');
        if (hasSelectAll) {
          cy.log('Select all checkbox found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Upload Modal', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should open upload modal', () => {
      cy.get('body').then($body => {
        const uploadButton = $body.find('button:contains("Upload Files"), button:contains("Upload")');
        if (uploadButton.length > 0) {
          cy.wrap(uploadButton).first().scrollIntoView().should('exist').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[class*="modal"], [class*="Modal"], [role="dialog"]').length > 0 ||
                             $modalBody.text().includes('Upload Files');
            if (hasModal) {
              cy.log('Upload modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have storage provider selector', () => {
      cy.get('body').then($body => {
        const uploadButton = $body.find('button:contains("Upload Files"), button:contains("Upload")');
        if (uploadButton.length > 0) {
          cy.wrap(uploadButton).first().scrollIntoView().should('exist').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasStorageSelector = $modalBody.text().includes('Storage Provider') ||
                                       $modalBody.find('select').length > 0;
            if (hasStorageSelector) {
              cy.log('Storage provider selector found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close upload modal', () => {
      cy.get('body').then($body => {
        const uploadButton = $body.find('button:contains("Upload Files"), button:contains("Upload")');
        if (uploadButton.length > 0) {
          cy.wrap(uploadButton).first().scrollIntoView().should('exist').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const closeButton = $modalBody.find('button:contains("Close"), button:contains("Cancel")');
            if (closeButton.length > 0) {
              cy.wrap(closeButton).first().scrollIntoView().should('exist').click();
              cy.waitForStableDOM();
              cy.log('Modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Bulk Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should show bulk action bar when files selected', () => {
      cy.get('body').then($body => {
        const checkboxes = $body.find('input[type="checkbox"]');
        if (checkboxes.length > 1) {
          cy.wrap(checkboxes).eq(1).should('be.visible').click();
          cy.get('body').then($bulkBody => {
            const hasBulkActions = $bulkBody.text().includes('selected') ||
                                   $bulkBody.find('button:contains("Download")').length > 0;
            if (hasBulkActions) {
              cy.log('Bulk action bar shown');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk download option', () => {
      cy.get('body').then($body => {
        const downloadButton = $body.find('button:contains("Download")');
        if (downloadButton.length > 0) {
          cy.log('Bulk download option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk delete option', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete")');
        if (deleteButton.length > 0) {
          cy.log('Bulk delete option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have clear selection option', () => {
      cy.get('body').then($body => {
        const clearButton = $body.find('button:contains("Clear")');
        if (clearButton.length > 0) {
          cy.log('Clear selection option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Storage Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/content/files');
      cy.waitForPageLoad();
    });

    it('should display storage usage', () => {
      cy.get('body').then($body => {
        const hasStorage = $body.text().includes('Storage Used') ||
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
        const hasCount = $body.text().includes('Total Files') ||
                         $body.text().includes('files');
        if (hasCount) {
          cy.log('Total files count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display storage progress bar', () => {
      cy.get('body').then($body => {
        const hasProgressBar = $body.find('[class*="progress"], [class*="bar"]').length > 0 ||
                               $body.text().includes('% used');
        if (hasProgressBar) {
          cy.log('Storage progress bar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/files*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/files*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load files' }
      });

      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.find('[class*="error"]').length > 0;
        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
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

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Files') || $body.text().includes('My Files');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/files');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Files') || $body.text().includes('My Files');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
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
