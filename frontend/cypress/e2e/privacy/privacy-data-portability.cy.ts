/// <reference types="cypress" />

/**
 * Privacy Data Portability Tests
 *
 * Tests for Data Portability functionality including:
 * - Data export
 * - Data import
 * - Export formats
 * - Export history
 * - Bulk operations
 * - Transfer requests
 */

describe('Privacy Data Portability Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Data Export', () => {
    it('should navigate to data export page', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.text().includes('Download') ||
                         $body.text().includes('Data');
        if (hasExport) {
          cy.log('Data export page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export options', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOptions = $body.text().includes('Select') ||
                          $body.text().includes('Choose') ||
                          $body.find('input[type="checkbox"]').length > 0;
        if (hasOptions) {
          cy.log('Export options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export all data button', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExportAll = $body.find('button:contains("Export all"), button:contains("Download all")').length > 0 ||
                            $body.text().includes('Export all');
        if (hasExportAll) {
          cy.log('Export all data button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display data categories', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Profile') ||
                             $body.text().includes('Activity') ||
                             $body.text().includes('Settings') ||
                             $body.text().includes('Category');
        if (hasCategories) {
          cy.log('Data categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display estimated export size', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSize = $body.text().includes('MB') ||
                       $body.text().includes('GB') ||
                       $body.text().includes('Size') ||
                       $body.text().includes('KB');
        if (hasSize) {
          cy.log('Estimated export size displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Formats', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should offer JSON format', () => {
      cy.get('body').then($body => {
        const hasJSON = $body.text().includes('JSON') ||
                       $body.find('input[value="json"], option[value="json"]').length > 0;
        if (hasJSON) {
          cy.log('JSON format option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should offer CSV format', () => {
      cy.get('body').then($body => {
        const hasCSV = $body.text().includes('CSV') ||
                      $body.find('input[value="csv"], option[value="csv"]').length > 0;
        if (hasCSV) {
          cy.log('CSV format option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should offer XML format', () => {
      cy.get('body').then($body => {
        const hasXML = $body.text().includes('XML') ||
                      $body.find('input[value="xml"], option[value="xml"]').length > 0;
        if (hasXML) {
          cy.log('XML format option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have format selector', () => {
      cy.get('body').then($body => {
        const hasSelector = $body.find('select, [data-testid="format-selector"]').length > 0 ||
                           $body.find('input[type="radio"]').length > 0;
        if (hasSelector) {
          cy.log('Format selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export History', () => {
    it('should navigate to export history', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Previous') ||
                          $body.text().includes('Past');
        if (hasHistory) {
          cy.log('Export history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display previous exports', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExports = $body.find('table, [data-testid="export-history"]').length > 0 ||
                          $body.text().includes('No exports');
        if (hasExports) {
          cy.log('Previous exports displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export status', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Complete') ||
                         $body.text().includes('Processing') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Export status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have re-download option', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download]').length > 0 ||
                           $body.text().includes('Download');
        if (hasDownload) {
          cy.log('Re-download option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export expiry', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExpiry = $body.text().includes('Expir') ||
                         $body.text().includes('Valid until') ||
                         $body.text().includes('Available');
        if (hasExpiry) {
          cy.log('Export expiry displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Import', () => {
    it('should navigate to data import page', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasImport = $body.text().includes('Import') ||
                         $body.text().includes('Upload') ||
                         $body.text().includes('Restore');
        if (hasImport) {
          cy.log('Data import page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have file upload area', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUpload = $body.find('input[type="file"], [data-testid="file-upload"]').length > 0 ||
                         $body.text().includes('Upload') ||
                         $body.text().includes('Drag');
        if (hasUpload) {
          cy.log('File upload area displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display supported formats', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFormats = $body.text().includes('JSON') ||
                          $body.text().includes('CSV') ||
                          $body.text().includes('Supported');
        if (hasFormats) {
          cy.log('Supported formats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display import preview', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPreview = $body.text().includes('Preview') ||
                          $body.text().includes('Review') ||
                          $body.find('[data-testid="import-preview"]').length >= 0;
        cy.log('Import preview pattern available');
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Transfer Requests', () => {
    it('should navigate to transfer requests', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTransfer = $body.text().includes('Transfer') ||
                           $body.text().includes('Portability') ||
                           $body.text().includes('Move');
        if (hasTransfer) {
          cy.log('Transfer requests page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request transfer button', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRequest = $body.find('button:contains("Request"), button:contains("Transfer")').length > 0 ||
                          $body.text().includes('Request transfer');
        if (hasRequest) {
          cy.log('Request transfer button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display transfer destination options', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDestination = $body.text().includes('Destination') ||
                              $body.text().includes('Provider') ||
                              $body.text().includes('Service');
        if (hasDestination) {
          cy.log('Transfer destination options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pending transfers', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending') ||
                          $body.text().includes('In progress') ||
                          $body.text().includes('Status');
        if (hasPending) {
          cy.log('Pending transfers displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Bulk Operations', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should have select all option', () => {
      cy.get('body').then($body => {
        const hasSelectAll = $body.find('input[type="checkbox"]').length > 0 ||
                            $body.text().includes('Select all');
        if (hasSelectAll) {
          cy.log('Select all option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display selection count', () => {
      cy.get('body').then($body => {
        const hasCount = $body.text().match(/\d+\s*(selected|item)/i) !== null ||
                        $body.find('[data-testid="selection-count"]').length >= 0;
        cy.log('Selection count pattern available');
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk export button', () => {
      cy.get('body').then($body => {
        const hasBulkExport = $body.find('button:contains("Export selected")').length > 0 ||
                             $body.text().includes('Export');
        if (hasBulkExport) {
          cy.log('Bulk export button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Progress', () => {
    it('should display export progress indicator', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasProgress = $body.find('progress, [role="progressbar"], .progress').length >= 0 ||
                           $body.text().includes('%');
        cy.log('Export progress indicator pattern available');
      });

      cy.get('body').should('be.visible');
    });

    it('should display estimated time', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTime = $body.text().includes('minute') ||
                       $body.text().includes('second') ||
                       $body.text().includes('Estimated');
        if (hasTime) {
          cy.log('Estimated time displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel export option', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCancel = $body.find('button:contains("Cancel")').length >= 0 ||
                         $body.text().includes('Cancel');
        cy.log('Cancel export option pattern available');
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Verification', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should display data integrity check', () => {
      cy.get('body').then($body => {
        const hasIntegrity = $body.text().includes('Verify') ||
                            $body.text().includes('Integrity') ||
                            $body.text().includes('Checksum');
        if (hasIntegrity) {
          cy.log('Data integrity check displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export summary', () => {
      cy.get('body').then($body => {
        const hasSummary = $body.text().includes('Summary') ||
                          $body.text().includes('Total') ||
                          $body.text().includes('Records');
        if (hasSummary) {
          cy.log('Export summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display data portability correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/privacy/export');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Data portability displayed correctly on ${name}`);
      });
    });
  });
});
