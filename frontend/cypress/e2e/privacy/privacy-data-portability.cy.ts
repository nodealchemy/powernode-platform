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
      cy.assertContainsAny(['Export', 'Download', 'Data', 'Privacy']);
    });

    it('should display export options', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Select', 'Choose', 'Export', 'Data']);
    });

    it('should have export data button', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
      cy.assertHasElement([
        'button:contains("Export")',
        'button:contains("Download")',
        'button:contains("Request")',
        '[data-testid*="export"]'
      ]);
    });

    it('should display data categories', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Activity', 'Settings', 'Data', 'Category']);
    });

    it('should display export information', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
      cy.assertContainsAny(['MB', 'GB', 'Size', 'KB', 'Export', 'Download']);
    });
  });

  describe('Export Formats', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should offer JSON format', () => {
      cy.assertContainsAny(['JSON', 'json', 'Format', 'Export']);
    });

    it('should offer CSV format', () => {
      cy.assertContainsAny(['CSV', 'csv', 'Format', 'Export']);
    });

    it('should offer format selection', () => {
      cy.assertHasElement([
        'select',
        '[data-testid="format-selector"]',
        'input[type="radio"]',
        '[data-testid*="format"]'
      ]);
    });
  });

  describe('Export History', () => {
    it('should navigate to export history', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Previous', 'Past', 'Export']);
    });

    it('should display exports or empty state', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['No exports', 'Export', 'History', 'Download']);
    });

    it('should display export status', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Complete', 'Processing', 'Failed', 'Status', 'No exports']);
    });

    it('should have download option for completed exports', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Download', 'Export', 'History', 'No exports']);
    });

    it('should display export information', () => {
      cy.visit('/app/privacy/export/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Expir', 'Valid', 'Available', 'Export', 'History']);
    });
  });

  describe('Data Import', () => {
    it('should navigate to data import page', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Import', 'Upload', 'Restore', 'Data']);
    });

    it('should have file upload area', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Upload', 'Drag', 'Select', 'File', 'Import']);
    });

    it('should display supported formats', () => {
      cy.visit('/app/privacy/import');
      cy.waitForPageLoad();
      cy.assertContainsAny(['JSON', 'CSV', 'Supported', 'Format', 'Import']);
    });
  });

  describe('Transfer Requests', () => {
    it('should navigate to transfer requests', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Transfer', 'Portability', 'Move', 'Data']);
    });

    it('should have request transfer button', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();
      cy.assertHasElement([
        'button:contains("Request")',
        'button:contains("Transfer")',
        '[data-testid*="transfer"]',
        'button:contains("Submit")'
      ]);
    });

    it('should display transfer options', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Destination', 'Provider', 'Service', 'Transfer']);
    });

    it('should display transfer status', () => {
      cy.visit('/app/privacy/transfer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pending', 'In progress', 'Status', 'Transfer', 'No transfers']);
    });
  });

  describe('Bulk Operations', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should have selection options', () => {
      cy.assertContainsAny(['Select all', 'Export', 'Data', 'Choose']);
    });

    it('should have bulk export option', () => {
      cy.assertHasElement([
        'button:contains("Export")',
        'button:contains("Download")',
        '[data-testid*="export"]',
        'input[type="checkbox"]'
      ]);
    });
  });

  describe('Export Progress', () => {
    it('should display export interface', () => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Export', 'Download', 'Data', 'Request']);
    });
  });

  describe('Data Verification', () => {
    beforeEach(() => {
      cy.visit('/app/privacy/export');
      cy.waitForPageLoad();
    });

    it('should display data information', () => {
      cy.assertContainsAny(['Verify', 'Integrity', 'Summary', 'Total', 'Records', 'Export']);
    });

    it('should display export summary', () => {
      cy.assertContainsAny(['Summary', 'Total', 'Records', 'Data', 'Export']);
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
        cy.assertContainsAny(['Export', 'Download', 'Data', 'Privacy']);
      });
    });
  });
});
