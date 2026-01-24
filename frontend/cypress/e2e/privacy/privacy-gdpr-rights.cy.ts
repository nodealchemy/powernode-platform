/// <reference types="cypress" />

/**
 * Privacy GDPR Rights Tests
 *
 * Tests for GDPR Data Subject Rights including:
 * - Right to access
 * - Right to rectification
 * - Right to erasure
 * - Right to portability
 * - Right to restriction
 * - Right to object
 */

describe('Privacy GDPR Rights Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('GDPR Rights Overview', () => {
    it('should navigate to GDPR rights page', () => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
      cy.assertContainsAny(['GDPR', 'Rights', 'Data Protection', 'Privacy']);
    });

    it('should display available rights', () => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Access', 'Delete', 'Export', 'Rights']);
    });
  });

  describe('Right to Access', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data access option', () => {
      cy.assertContainsAny(['Access', 'View my data', 'See what', 'Your Data']);
    });

    it('should have request data access button', () => {
      cy.assertHasElement([
        'button:contains("Request")',
        'button:contains("Access")',
        'button:contains("View")',
        '[data-testid*="access"]'
      ]);
    });

    it('should display data categories', () => {
      cy.assertContainsAny(['Profile', 'Activity', 'Payment', 'Usage', 'Data']);
    });
  });

  describe('Right to Erasure', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display delete data option', () => {
      cy.assertContainsAny(['Delete', 'Erasure', 'Remove', 'Right to']);
    });

    it('should have request deletion button', () => {
      cy.assertHasElement([
        'button:contains("Delete")',
        'button:contains("Request deletion")',
        'button:contains("Erase")',
        '[data-testid*="delete"]'
      ]);
    });

    it('should display deletion warning', () => {
      cy.assertContainsAny(['Warning', 'permanent', 'cannot be undone', 'Delete', 'irreversible']);
    });
  });

  describe('Right to Portability', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data export option', () => {
      cy.assertContainsAny(['Export', 'Download', 'Portability', 'Your Data']);
    });

    it('should have export format options', () => {
      cy.assertContainsAny(['JSON', 'CSV', 'Format', 'Export', 'Download']);
    });

    it('should have request export button', () => {
      cy.assertHasElement([
        'button:contains("Export")',
        'button:contains("Download")',
        'button:contains("Request")',
        '[data-testid*="export"]'
      ]);
    });
  });

  describe('Right to Rectification', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data correction option', () => {
      cy.assertContainsAny(['Correct', 'Update', 'Rectif', 'Edit', 'Modify']);
    });

    it('should link to profile editing', () => {
      cy.assertHasElement([
        'a[href*="profile"]',
        'a:contains("Edit")',
        'button:contains("Edit")',
        '[data-testid*="edit"]'
      ]);
    });
  });

  describe('Right to Restriction', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display processing restriction option', () => {
      cy.assertContainsAny(['Restrict', 'Limit', 'Processing', 'Right to']);
    });
  });

  describe('Right to Object', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display marketing objection option', () => {
      cy.assertContainsAny(['Marketing', 'Object', 'Unsubscribe', 'Opt-out']);
    });

    it('should display profiling objection option', () => {
      cy.assertContainsAny(['Profiling', 'Automated', 'Decision', 'Object']);
    });
  });

  describe('Request History', () => {
    it('should display request history', () => {
      cy.visit('/app/account/privacy/requests');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Request', 'Previous', 'Requests']);
    });

    it('should display request status', () => {
      cy.visit('/app/account/privacy/requests');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pending', 'Completed', 'Processing', 'Status', 'No requests']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display GDPR rights correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/privacy/gdpr');
        cy.waitForPageLoad();
        cy.assertContainsAny(['GDPR', 'Rights', 'Privacy', 'Data']);
      });
    });
  });
});
