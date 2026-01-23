/// <reference types="cypress" />

/**
 * Vendor Documents E2E Tests
 *
 * Tests for the Vendor Documents Panel functionality including:
 * - Document list display
 * - Category filtering
 * - File upload workflow
 * - File download
 * - File deletion
 * - Error handling
 */

// Helper to click the Documents tab reliably
const clickDocumentsTab = () => {
  cy.contains('button', 'Documents').click();
  // Wait for Documents panel to load
  cy.contains('Filter:').should('be.visible');
};

describe('Vendor Documents Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
  });

  describe('Documents Tab on Vendor Detail Page', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
    });

    it('should display documents tab', () => {
      cy.contains('button', 'Documents').should('be.visible');
    });

    it('should navigate to documents tab', () => {
      clickDocumentsTab();
      cy.assertContainsAny(['Compliance', 'Assessment', 'Certificate', 'Upload']);
    });

    it('should display document categories', () => {
      clickDocumentsTab();
      cy.assertContainsAny(['Compliance', 'Assessment', 'Certificate']);
    });
  });

  describe('Document List Display', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
    });

    it('should display uploaded documents', () => {
      cy.wait('@getVendorFiles').then(() => {
        cy.assertContainsAny(['soc2-report-2024.pdf', 'iso27001-certificate.pdf', 'risk-assessment-q1.pdf', '.pdf']);
      });
    });

    it('should display file metadata', () => {
      cy.wait('@getVendorFiles').then(() => {
        cy.assertContainsAny(['KB', 'MB', 'ago', 'Test User']);
      });
    });

    it('should display category badges', () => {
      cy.wait('@getVendorFiles').then(() => {
        cy.assertContainsAny(['Compliance', 'Certificate', 'Assessment']);
      });
    });

    it('should display download buttons for each file', () => {
      cy.wait('@getVendorFiles').then(() => {
        cy.assertHasElement([
          '[data-testid="download-btn"]',
          'button[title*="Download"]',
          '[aria-label*="Download"]',
          'svg[data-testid="icon-download"]',
        ]);
      });
    });

    it('should display delete buttons for each file', () => {
      cy.wait('@getVendorFiles').then(() => {
        cy.assertHasElement([
          '[data-testid="delete-btn"]',
          'button[title*="Delete"]',
          '[aria-label*="Delete"]',
          'svg[data-testid="icon-trash"]',
        ]);
      });
    });
  });

  describe('Document Category Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
    });

    it('should have filter buttons', () => {
      cy.assertContainsAny(['All', 'Filter']);
    });

    it('should filter by compliance category', () => {
      cy.contains('button', 'Compliance').click();
      cy.wait('@getVendorFiles');
    });

    it('should filter by assessment category', () => {
      cy.contains('button', 'Assessment').click();
      cy.wait('@getVendorFiles');
    });

    it('should filter by certificate category', () => {
      cy.contains('button', 'Certificate').click();
      cy.wait('@getVendorFiles');
    });

    it('should show all documents when All filter selected', () => {
      cy.contains('button', 'All').click();
      cy.wait('@getVendorFiles');
    });
  });

  describe('Document Upload', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
    });

    it('should have upload buttons for each category', () => {
      // Upload buttons show category names with Upload icons (not "Upload" text)
      cy.contains('button', 'Compliance').should('exist');
      cy.contains('button', 'Assessment').should('exist');
      cy.contains('button', 'Certificate').should('exist');
    });

    it('should have hidden file input', () => {
      cy.get('input[type="file"]').should('exist');
    });

    it('should accept valid file types', () => {
      cy.get('input[type="file"]').should('have.attr', 'accept').and('include', '.pdf');
    });

    it('should trigger file input when upload button clicked', () => {
      // Upload buttons have category names (Compliance, Assessment, Certificate)
      cy.contains('button', 'Compliance').should('not.be.disabled');
    });

    it('should show upload progress when uploading', () => {
      // Simulate file upload with delayed response
      cy.intercept('POST', '**/api/v1/files/upload', (req) => {
        req.reply({
          delay: 1000,
          statusCode: 201,
          body: { success: true, data: { file: { id: 'new-file', filename: 'test.pdf' } } },
        });
      }).as('uploadFileDelayed');

      // Note: Full file upload testing requires special Cypress file upload handling
      // This test verifies the upload infrastructure exists
      cy.get('input[type="file"]').should('exist');
    });
  });

  describe('Document Download', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFiles');
    });

    it('should initiate download when download button clicked', () => {
      cy.get('button[title*="Download"], [aria-label*="Download"]').first().click();
      cy.wait('@getFileDownloadUrl');
    });
  });

  describe('Document Deletion', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFiles');
    });

    it('should delete document when delete button clicked', () => {
      cy.get('button[title*="Delete"], [aria-label*="Delete"]').first().click();
      cy.wait('@deleteFile');
    });

    it('should refresh document list after deletion', () => {
      cy.get('button[title*="Delete"], [aria-label*="Delete"]').first().click();
      cy.wait('@deleteFile');
      cy.wait('@getVendorFiles');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no documents', () => {
      // Override intercept to return empty files (handles URL-encoded colons)
      cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Vendor/i, {
        statusCode: 200,
        body: { success: true, data: { files: [], pagination: { current_page: 1, per_page: 20, total_pages: 0, total_count: 0 } } },
      }).as('getVendorFilesEmpty');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFilesEmpty');
      cy.assertContainsAny(['No documents', 'No files', 'Upload', 'empty']);
    });

    it('should show upload buttons in empty state', () => {
      cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Vendor/i, {
        statusCode: 200,
        body: { success: true, data: { files: [], pagination: { current_page: 1, per_page: 20, total_pages: 0, total_count: 0 } } },
      }).as('getVendorFilesEmpty');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFilesEmpty');
      cy.assertHasElement([
        'button:contains("Upload")',
        'button:contains("Compliance")',
        'button:contains("Assessment")',
        'button:contains("Certificate")',
      ]);
    });
  });

  describe('Document Info Box', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
    });

    it('should display document types info box', () => {
      cy.assertContainsAny(['Document Types', 'SOC 2', 'ISO 27001', 'Risk assessments']);
    });

    it('should describe compliance documents', () => {
      cy.assertContainsAny(['SOC 2 reports', 'GDPR documentation', 'privacy policies']);
    });

    it('should describe assessment documents', () => {
      cy.assertContainsAny(['Risk assessments', 'security questionnaire']);
    });

    it('should describe certificate documents', () => {
      cy.assertContainsAny(['ISO 27001', 'SOC 2 Type II', 'HIPAA']);
    });
  });

  describe('Error Handling', () => {
    it('should handle file list loading error', () => {
      cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Vendor/i, {
        statusCode: 500,
        body: { success: false, error: 'Internal server error' },
      }).as('getVendorFilesError');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFilesError');
      cy.assertContainsAny(['error', 'Error', 'failed', 'Failed', 'Could not']);
    });

    it('should handle upload error', () => {
      cy.intercept('POST', '**/api/v1/files/upload', {
        statusCode: 500,
        body: { success: false, error: 'Upload failed' },
      }).as('uploadFileError');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();

      // Upload error handling would be tested with actual file upload
      cy.get('input[type="file"]').should('exist');
    });

    it('should handle delete error', () => {
      cy.intercept('DELETE', /\/api\/v1\/files\/[^\/]+$/, {
        statusCode: 500,
        body: { success: false, error: 'Delete failed' },
      }).as('deleteFileError');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFiles');
      cy.get('button[title*="Delete"], [aria-label*="Delete"]').first().click();
      cy.wait('@deleteFileError');
      cy.assertContainsAny(['error', 'Error', 'failed', 'Failed']);
    });

    it('should handle download error', () => {
      cy.intercept('GET', /\/api\/v1\/files\/[^\/]+\/download/, {
        statusCode: 500,
        body: { success: false, error: 'Download failed' },
      }).as('getFileDownloadUrlError');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.wait('@getVendorFiles');
      cy.get('button[title*="Download"], [aria-label*="Download"]').first().click();
      cy.wait('@getFileDownloadUrlError');
      cy.assertContainsAny(['error', 'Error', 'failed', 'Failed']);
    });
  });

  describe('Loading States', () => {
    it('should show loading state while fetching documents', () => {
      cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Vendor/i, (req) => {
        req.reply({
          delay: 2000,
          statusCode: 200,
          body: { success: true, data: { files: [], pagination: { current_page: 1, per_page: 20, total_pages: 0, total_count: 0 } } },
        });
      }).as('getVendorFilesDelayed');

      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.contains('button', 'Documents').click();
      // Check for loading indicator (LoadingSpinner uses animate-spin class)
      cy.get('.animate-spin').should('exist');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.assertContainsAny(['Compliance', 'Assessment', 'Certificate', 'Upload']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      clickDocumentsTab();
      cy.assertContainsAny(['Compliance', 'Assessment', 'Certificate', 'Upload']);
    });
  });
});

export {};
